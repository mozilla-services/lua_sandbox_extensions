-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Taskcluster Live Backing Log Decoder Module.
Parses the Taskcluster live_backing.log

## Decoder Configuration Table
decoders_taskcluster_live_backing_log = {
    -- perfherder_schema = "/usr/share/luasandbox/schemas/taskcluster/perfherder.1.schema.json" -- default
}

## Functions

### decode

Decode and inject the resulting message

*Arguments*
- data (string) - Data to write to the msg.Payload
- default_headers (optional table) - Heka message table containing the default
  header values to use, if they are not populated by the decoder. If 'Fields'
  is specified it should be in the hashed based format see:
  http://mozilla-services.github.io/lua_sandbox/heka/message.html

*Return*
- nil - throws an error on inject_message failure.

--]]

-- Imports
local module_name   = ...
local string        = require "string"
local module_cfg    = string.gsub(module_name, "%.", "_")
local cfg           = read_config(module_cfg) or {}
assert(type(cfg) == "table", module_cfg .. " must be a table")

local bg        = require "lpeg.printf".build_grammar
local cjson     = require "cjson"
local rjson     = require "rjson"
local date      = require "date"
local dt        = require "lpeg.date_time"
local io        = require "io"
local l         = require "lpeg";l.locale(l)
local os        = require "os"
local sdu       = require "lpeg.sub_decoder_util"
local string    = require "string"
local table     = require "table"

local assert    = assert
local ipairs    = ipairs
local pairs     = pairs
local pcall     = pcall
-- local print     = print
local tostring  = tostring
local tonumber  = tonumber
local type      = type

local inject_message = inject_message
local read_config    = read_config

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local time          = l.Ct(dt.date_fullyear * "-" * dt.date_month * "-" * dt.date_mday * l.S"T " * dt.time_hour * ":" * dt.time_minute * ":" * dt.time_second * dt.time_secfrac^-1 * "Z")
local time_header   = l.P"[" * l.Cg(l.alpha^1, "name") * l.space^1 * l.Cg(time, "date_time") * "]" * l.space^1
local task_header   = l.Cg(l.Ct(dt.time_hour * ":" * dt.time_minute * ":" * dt.time_second), "time") * l.space^1 * l.Cg(l.alpha^1, "priority") * l.space^1 * "-"
local message       = l.space^0 * l.Cg((l.P(1) - (l.space^0 * l.P(-1)))^1, "msg")
local log_line      = l.Ct((time_header^-1 * task_header^-1) * message)

local schemas_map = {}
local perfherder_schema_file = cfg.perfherder_schema  or "/usr/share/luasandbox/schemas/taskcluster/perfherder.1.schema.json"
local fh = assert(io.open(perfherder_schema_file, "r"))
local perfherder_schema = fh:read("*a")
perfherder_schema = rjson.parse_schema(perfherder_schema)
fh:close()


local function add_fields(msg, fields)
    if not fields then return end

    if msg.Fields then
        for k,v in pairs(fields) do
            msg.Fields[k] = v
        end
    else
        msg.Fields = fields
    end
    msg.Fields["_"] = nil
end


local function merge_table(dest, src)
    for k,v in pairs(src) do
        dest[k] = v
    end
end

local result_exit_code = l.Cg(l.digit^1 / function(s) if s == "0" then return "success" end return "failed" end, "result")
local normalize_test = (l.P(1) - "/tests/")^0 * l.C(l.P(1)^1) + l.Carg(1)
local base_msg   = nil
local function inject_message_mod(g, level, fields)
    local msg = sdu.copy_message(base_msg, false)
    msg.Type                    = "timing"
    msg.Fields.component        = g.Component
    msg.Fields.sub_component    = g.SubComponent
    if not fields.result then fields.result = "success" end
    add_fields(msg, fields)

    if g.Component == "test" then
        msg.Fields.file = normalize_test:match(msg.Fields.file, nil, msg.Fields.file)
    end

    msg.Fields.level = level
    msg.Fields.duration = (msg.Fields.log_end - msg.Fields.log_start) / 1e9
    msg.Fields.log_start = date.format(msg.Fields.log_start, "%Y-%m-%dT%H:%M:%SZ")
    msg.Fields.log_end = date.format(msg.Fields.log_end, "%Y-%m-%dT%H:%M:%SZ")
    msg.Fields.result = string.lower(msg.Fields.result)
    msg.Payload = cjson.encode(msg.Fields)
    inject_message(msg)
end


local doc = rjson.parse("{}") -- reuse this object to avoid creating a lot of GC
local vcs_suites = {clone = true, pull = true, update = true}
local function perfherder(g, b, json)
    local j = cjson.decode(json)
    if type(j.framework) ~= "table" then return false end

    local line = b.current
    local ns = dt.time_to_ns(line.date_time)
    if j.framework.name == "vcs" then
        for _,v in ipairs(j.suites) do
            if vcs_suites[v.name] then
                local f = {
                    component = j.framework.name,
                    sub_component = v.name,
                    log_start = ns - v.value * 1e9,
                    log_end   = ns,
                }
                if line.date_time == line.pts then
                    f.log_start = ns
                    f.log_end   = ns + v.value * 1e9
                end
                inject_message_mod(g, b.level, f)
            end
        end
    elseif j.framework.name == "build_metrics" then
        for _,v in ipairs(j.suites) do
            if v.name == "build times" then
                local bg = b.stack[b.level]
                local bc = b.cache[bg]
                local ns = 0
                if bc and bc.log_start then
                    ns = bc.log_start -- overlay the time stamps into the parent block i.e. mozharness
                else
                    ns = dt.time_to_ns(b.pmts)
                end
                local f = {
                    component = j.framework.name,
                    sub_component = v.name,
                    log_end = ns,
                }
                for _,r in ipairs(v.subtests) do
                    f.sub_component = r.name
                    f.log_start = f.log_end
                    f.log_end = f.log_end + r.value * 1e9
                    inject_message_mod(g, b.level, f)
                end
            end
        end
    -- fix up inconsistent schemas
    elseif j.framework.name == "js-bench" then
        for i,v in ipairs(j.suites) do
            v.unit = v.units
            v.units = nil
        end
    elseif j.framework.name == "awsy" then
        for i,v in ipairs(j.suites) do
            for m,n in ipairs(v.subtests) do
                n.unit = n.units
                n.units = nil
            end
            v.unit = v.units
            v.units = nil
        end
    end
    j.time      = date.format(ns, "%Y-%m-%dT%H:%M:%SZ")
    j.task      = base_msg.Fields["task"]
    j.project   = base_msg.Fields["origin_project"]
    j.platform  = base_msg.Fields["machine_platform"]
    j.revision  = base_msg.Fields["origin_revision"]
    j.pushLogID = base_msg.Fields["origin_pushlog_id"]
    j.framework = j.framework.name
    local payload = cjson.encode(j)
    doc:parse(payload)
    local ok, err, report = doc:validate(perfherder_schema)
    if not err then
        local msg = {
            Type = "perfherder",
            Payload = payload,
            Fields = {
                machine_platform = j.platform,
                job_symbol = base_msg.Fields["job_symbol"],
                group_symbol = base_msg.Fields["group_symbol"],
                framework = j.framework,
                project = j.project,
                platform = j.platform
            }
        }
        inject_message(msg)
    else
        local msg = {
            Type = "error.perfherder.validation",
            Payload = err,
            Fields = {
                schema = perfherder_schema_file,
                error_detail = report,
                data = payload
            }
        }
        inject_message(msg)
    end
    return true
end


local function set_date_time(f, b)
    if f.date_time then
        b.current.date_time = f.date_time
        f.date_time = nil
    end
    return dt.time_to_ns(b.current.date_time)
end


local function eval_log(g, b)
    local cache = b.cache[g]
    if g.Sequence then
        for i = cache.sidx, #g.Sequence do
            local v = g.Sequence[i]
            local nmcb = b.next_match_cb
            local matched = v.fn(v, b)
            if matched then
                if nmcb then
                    nmcb(b.current.date_time)
                    if b.next_match_cb == nmcb then
                        b.next_match_cb = nil
                    end
                end
                b.pmts = b.current.date_time
                cache.sidx = i -- top level log sequences are treated as ordered and zero or one instance
                return true
            end
        end
    end
    return false
end


local function eval_end_block(g, b, level, cache)
    local f = g.End:match(b.current.msg)
    if not f then return false end

    b.stack[level] = nil
    b.level = level - 1
    f.log_end = set_date_time(f, b)
    cache.log_end = f.log_end
    if g.EndPrev then
        local prev = b.buffer_head + 1
        if prev == 4 then prev = 1 end
        local t = g.EndPrev:match(b.buffer[prev].msg)
        if t then merge_table(f, t) end
    end

    merge_table(cache.Fields, f)
    if not g.cache_on_completion then
        inject_message_mod(g, b.level, cache.Fields)
        b.cache[g] = nil
    end
    return true
end


local function eval_block(g, b)
    local matched = false
    local cache = b.cache[g]
    if not cache then
        local f = g.Start:match(b.current.msg)
        if f then
            b.level = b.level + 1
            b.stack[b.level] = g
            f.log_start = set_date_time(f, b)
            cache = {sidx = 1}
            b.cache[g] = cache
            cache.log_start = f.log_start
            cache.Fields = f
            return true
        end
    else
        matched = eval_end_block(g, b, b.level, cache)
        if not matched and g.Sequence then
            for i = cache.sidx, #g.Sequence do
                local v = g.Sequence[i]
                local nmcb = b.next_match_cb
                matched = v.fn(v, b)
                if matched then
                    if nmcb then
                        nmcb(b.current.date_time)
                        if b.next_match_cb == nmcb then
                            b.next_match_cb = nil
                        end
                    end
                    b.pmts = b.current.date_time
                    cache.sidx = 1 -- nested block sequences are treated as unordered and zero or more instances
                    return true
                end
            end
        end
        local level = b.level - 1 -- check for the end of the outer blocks since mal-formed logs are not uncommon
        while not matched and level > 1  do
            g = b.stack[level]
            cache = b.cache[g]
            matched = eval_end_block(g, b, level, cache)
            level = level - 1
        end
    end
    return matched
end


local function eval_tc_task_exit(g, b)
    local f = g.Grammar:match(b.current.msg)
    if not f then return false end

    b.tc_task_result = f.result
    return true
end


local function eval_line(g, b)
    local f = g.Grammar:match(b.current.msg)
    if not f then return false end

    f.log_start = set_date_time(f, b)
    f.log_end   = f.log_start
    if f.s then
        f.log_start = f.log_end - f.s * 1e9
        f.s = nil
    elseif f.ms then
        f.log_start = f.log_end - f.ms * 1e6
        f.ms = nil
    end
    inject_message_mod(g, b.level, f)
    return true
end


local function eval_line_n(g, b)
    local f = g.Grammar:match(b.current.msg)
    if not f then return false end

    f.log_start = set_date_time(f, b)
    f.log_end = dt.time_to_ns(b.buffer[b.buffer_head].date_time)
    inject_message_mod(g, b.level, f)
    return true
end


local function eval_line_pm(g, b)
    local f = g.Grammar:match(b.current.msg)
    if not f then return false end

    f.log_start = dt.time_to_ns(b.pmts)
    f.log_end = set_date_time(f, b)
    inject_message_mod(g, b.level, f)
    return true
end


local function eval_line_nm(g, b)
    local f = g.Grammar:match(b.current.msg)
    if not f then return false end

    f.log_start = set_date_time(f, b)
    b.next_match_cb = function(ts)
        f.log_end = dt.time_to_ns(ts)
        inject_message_mod(g, b.level, f)
    end
    return true
end


local function eval_line_js(g, b)
    local json = g.Grammar:match(b.current.msg)
    if not json then return false end

    local ok, err = pcall(g.fn_js, g, b, json)
    if not ok then
        inject_message({
            Type = "error.perfherder.parse",
            Payload = err,
            Fields = {
                data = json
            }
        })
    end
    return true
end


local function new_log(sequence)
    return {
        Type        = "block",
        Component   = "task",
        SubComponent= "total",
        Sequence    = sequence,
        fn          = eval_log,
    }
end


local normalize_result = (l.P"successful" + "succeeded") / "success" + (l.P"unsuccessful" + "error" + "fail") / "failed" + l.Carg(1)
local function new_task_completion(g, b, cache)
    local sof = dt.time_to_ns(b.sts)
    local eof = dt.time_to_ns(b.pts)
    local f = {
        component     = g.Component,
        sub_component = g.SubComponent,
        log_start     = sof,
        log_end       = eof,
        result        = "success",
    }
    local level = 1
    local result = string.lower(cache.Fields.result or b.tc_task_result or b.tc_result)
    result = normalize_result:match(result, nil, result)

    if cache.log_start and cache.log_end then
        f.log_start = sof
        f.log_end = cache.log_start
        f.sub_component = "setup"
        inject_message_mod(g, level, f)

        cache.Fields.result = result
        inject_message_mod(g, level, cache.Fields)

        f.log_start = cache.log_end
        f.log_end = eof
        f.sub_component = "teardown"
        inject_message_mod(g, level, f)
        b.cache[g] = nil
    else
        f.result = result
        inject_message_mod(g, level, f)
    end
end


local function new_task(sequence)
    return {
        Type        = "block",
        Component   = "taskcluster",
        SubComponent= "task",
        Start       = bg{"=== Task Starting ==="},
        End         = bg{"=== Task Finished ==="},
        EndPrev     = bg{"Result: %s", "result"},
        Sequence    = sequence,
        cache_on_completion = new_task_completion,
        fn          = eval_block,
    }
end


local function new_mozharness(sequence)
    return {
        Type        = "block",
        Component   = "mozharness",
        SubComponent= nil, -- set by the parser
        Start       = bg{"[mozharness: %s] Running %s.", l.Cg(time, "date_time"), "sub_component"},
        End         = bg{"[mozharness: %s] Finished %s (%s)", l.Cg(time, "date_time"), "sub_component", "result"},
        Sequence    = sequence,
        fn          = eval_block
    }
end


local task_exit = {
    Type        = "task_exit",
    Grammar     = bg{"%s task run with exit code: %d completed in %g seconds", "_", result_exit_code, "_"},
    fn          = eval_tc_task_exit
}


local perfherder = {
    Type        = "line_js",
    Component   = "perfherder",
    SubComponent= nil, -- set by the parser
    Grammar     = l.P"raptor-output "^-1 * l.P"PERFHERDER_DATA: " * l.C(l.P(1)^1),
    fn          = eval_line_js,
    fn_js       = perfherder
}


local gecko = {
    Type        = "block",
    Component   = "gecko",
    SubComponent= "startup",
    Start       = bg{"TEST-INFO | started process GECKO(%d)", "_"},
    End         = bg{"SimpleTest START"}
                    + bg{"*** Start BrowserChrome Test Results ***"}
                    + bg{"TEST-START"}
                    + bg{"TEST-INFO | Main app process: exit %d", result_exit_code},
    fn          = eval_block
}


local test_errors = l.P"TIMEOUT" + "ERROR" + "FAIL" + "KNOWN-FAIL(EXPECTED RANDOM)" + "KNOWN-FAIL" + "UNEXPECTED-FAIL" + "UNEXPECTED-TIMEOUT" + "UNEXPECTED-NOTRUN" + "END" -- most of these don't have timing
local test_status = l.P"TEST-" * l.Cg((l.P"OK" + test_errors), "result")
local test = {
    Type        = "line",
    Component   = "test",
    SubComponent= "general",
    Grammar     = bg{"%s | %s | took %dms", test_status, "file", "ms"},
    fn          = eval_line
}


local gtest_status = l.P"TEST-" * l.Cg((l.P"PASS" + test_errors), "result")
local test_gtest = {
    Type        = "line",
    Component   = "test",
    SubComponent= "gtest",
    Grammar     = bg{"%s | %s | test completed (time: %dms)", gtest_status, "file", "ms"},
    fn          = eval_line
}


local reftest_status = l.P"REFTEST TEST-" * l.Cg((l.P"PASS(EXPECTED RANDOM)" + "PASS" + "SKIP" + test_errors), "result")
local test_ref = {
    Type        = "block",
    Component   = "test",
    SubComponent= "ref",
    Start       = bg{"REFTEST TEST-START | %s == %s", "file", "_"},
    End         = bg{"%s | %s %s", reftest_status, "file", l.P(1)^0},
    fn          = eval_block
}


local hazard_build = {
    Type            = "line_pm",
    Component       = "hazard",
    SubComponent    = "build",
    Grammar         = bg{"build finished (status %d): %s", result_exit_code, "_"},
    fn              = eval_line_pm
}


local hazard_gen = {
    Type            = "line_nm",
    Component       = "hazard",
    SubComponent    = nil, -- set by the parser
    Grammar         = bg{"Running %s to generate %s", "sub_component", "_"},
    fn              = eval_line_nm
}


local download = {
    Type        = "block",
    Component   = "artifact",
    SubComponent= "download",
    Start       = l.Ct(l.digit^1 * ":" * l.digit^1 * "." * l.digit^0 * l.space * "Downloading " * l.Cg((1 - l.space)^1, "file") * l.P(-1)),
    End         = bg{"%d:%d.%d Downloaded artifact to %s", "_", "_", "_", "_"},
    fn          = eval_block
}


local package_tests = {
    Type        = "line",
    Component   = "package",
    SubComponent= "tests",
    Grammar     = bg{"package-tests> Wrote %d files in %d bytes to %s in %gs", "_", "_", "file", "s"},
    fn          = eval_line
}


local upload = {
    -- estimate duration based on the number of bytes and a 1Gb connection
    -- The upload doesn't actually take place here it is part of the taskcluster teardown.
    -- Windows system output those stats after the task end but Linux systems
    -- don't so they will just be tracked this way for consistently
    Type        = "line_n",
    Component   = "artifact",
    SubComponent= "upload",
    Grammar     = bg{"upload> %s sha512 %d %s", "_", l.Cg(l.digit^1 / function(bytes) return tonumber(bytes)  / (1e9 / 8 * 0.8) end, "s"), "file"},
    fn          = eval_line
}


local function find_live_backing_log(a)
    local task, url
    for i,v in ipairs(a) do
        if v.url:match("live_backing.log$") then
            url  = v.url
            task = v.url:match("/task/([^/]+)/")
            break
        end
    end
    return task, url
end


local function normalize_platform(platform)
    local p = string.lower(platform)
    if p:match("win") then return "win" end
    if p:match("linux") then return "linux" end
    if p:match("android") then return "android" end
    if p:match("osx") then return "osx" end
    return "other"
end


local function finalize_log(g, b)
    local sof = dt.time_to_ns(b.sts)
    local eof = dt.time_to_ns(b.pts)
    local f = {
        component     = g.Component,
        sub_component = g.SubComponent,
        result        = b.tc_result,
        log_start     = sof,
        log_end       = eof,
    }
    inject_message_mod(g, 0, f)

    if not g.Sequence then return end

    local errors = {}
    for k,v in pairs(b.cache) do
        if k.cache_on_completion then
            k.cache_on_completion(k, b, v)
            v = b.cache[k] -- completion can clear the cache, so reset the state
        end
        if v and v.Fields then
            errors[#errors + 1] = string.format("Grammar %s, %s unfinished", k.Component, tostring(v.Fields.sub_component or k.SubComponent))
        end
    end

    if #errors > 0 and base_msg.Fields["result"] ~= "fail" then
        local msg = {
            Type = "error.log.schema",
            Payload = "unclosed block",
            Fields = {
                error_detail = table.concat(errors, "|"),
                data = b.job
            }
        }
        inject_message(msg)
    end
end


local integration_key = "other_kitchen-sink_test"
local no_schema = new_log()
local log_file = "/var/tmp/" .. read_config("Logger") .. ".txt"
function decode(data, dh, mutable)
    local j = cjson.decode(data)
    if j.state ~= "completed"
    or not j.timeScheduled
    or not j.timeStarted
    or not j.timeCompleted then
        return
    end

    local task, url = find_live_backing_log(j.logs)
    if not task then return end

    if dh and dh.integration_test then
        if not schemas_map[integration_key] then
            schemas_map[integration_key] = new_log({new_task({new_mozharness({upload,download,perfherder,test,test_ref,test_gtest,gecko,hazard_build,hazard_gen,package_tests}),perfherder}),task_exit})
        end
        log_file = dh.integration_test
        dh = nil
    else
        local rv = os.execute(string.format("curl %s -o %s -L -s --compressed", url, log_file))
        if rv ~= 0 then return string.format("curl rv: %d, %s", rv, url) end
    end

    base_msg = sdu.copy_message(dh, mutable)
    if not base_msg.Fields then base_msg.Fields = {} end
    base_msg.Fields["group_symbol"]     = j.display.groupSymbol or ""
    base_msg.Fields["job_kind"]         = j.jobKind or "unknown"
    base_msg.Fields["job_symbol"]       = j.display.jobSymbol or "unknown"
    base_msg.Fields["labels"]           = j.labels
    base_msg.Fields["machine_name"]     = j.buildMachine.name or "unknown"
    base_msg.Fields["machine_platform"] = j.buildMachine.platform or "unknown"
    base_msg.Fields["origin_kind"]      = j.origin.kind or "unknown"
    base_msg.Fields["origin_project"]   = j.origin.project or "unknown"
    base_msg.Fields["origin_pushlog_id"]= j.origin.pushLogID
    base_msg.Fields["origin_revision"]  = j.origin.revision or "unknown"
    base_msg.Fields["owner"]            = j.owner or "unknown"
    base_msg.Fields["result"]           = j.result or "unknown"
    base_msg.Fields["retry_id"]         = j.retryId or 0
    base_msg.Fields["task"]             = task
    base_msg.Fields["tier"]             = j.tier or 0
    base_msg.Fields["time_scheduled"]   = j.timeScheduled
    base_msg.Fields["time_started"]     = j.timeStarted
    base_msg.Fields["time_completed"]   = j.timeCompleted

    local np = normalize_platform(j.buildMachine.platform)
    local key = np .. "_" .. j.display.jobSymbol .. "_" .. j.display.groupSymbol
    local g = schemas_map[key]
    if not g then
        -- don't bother fetching and parsing logs with no schema/grammar
        -- however most do contain a last line of 'exit code: %d'
        -- if in the future we need a more accurate result
        local f = {
            log_start = dt.time_to_ns(time:match(j.timeStarted)),
            log_end = dt.time_to_ns(time:match(j.timeCompleted))
            }
        inject_message_mod(no_schema, 0, f)
        return
    end

    -- the timeStarted does not match what is in the log only use it as a last resort
    local state = {
        stack = {g},
        level = 1,
        sts = nil,
        pts = time:match(j.timeStarted),
        pmts = nil,
        next_match_cb = nil,
        tc_result = j.result,
        tc_task_result = nil,
        buffer = {nil, nil, nil},
        buffer_head = 0,
        current = nil,
        cache = {[g] = {sidx = 1}},
        job = data
    }
    state.pmts = state.pts

    local cnt = 0
    local fh = assert(io.open(log_file, "rb"))
    for line in fh:lines() do
        local data = log_line:match(line)
        if data then
            if not data.date_time then
                if data.time then
                    if data.time.hour < state.pts.hour then -- day wrapped
                        local timet = os.time(state.pts) + 86400
                        data.date_time = os.date("*t", timet)
                    else
                        data.date_time = {year = state.pts.year, month = state.pts.month, day = state.pts.day}
                    end
                    data.date_time.hour = data.time.hour
                    data.date_time.min  = data.time.min
                    data.date_time.sec  = data.time.sec
                    data.date_time.sec_frac = 0
                else
                    data.date_time = state.pts
                end
            end
            state.current = state.buffer[state.buffer_head]
            state.buffer_head = state.buffer_head + 1
            if state.buffer_head > 3 then state.buffer_head = 1 end
            state.buffer[state.buffer_head] = data

            if state.current then
                local block = state.stack[state.level]
                block.fn(block, state)
            end
            state.pts = data.date_time
            if not state.sts then
                state.sts = {year = state.pts.year, month = state.pts.month, day = state.pts.day,
                    hour = state.pts.hour, min = state.pts.min, sec = state.pts.sec, sec_frac = state.pts.sec_frac}
            end
        end
        cnt = cnt + 1
    end
    state.current = state.buffer[state.buffer_head] -- process the last line
    if state.current then
        g.fn(g, state) -- scan from the root and check everything incase the log was mal-formed
    end

    if not state.sts then -- no timing information in the log, use what was provided in the jobs.json
        state.sts = state.pts
        state.pts = time:match(j.timeCompleted)
    end
    finalize_log(g, state)
    --print(string.format("log_file: %s processed %d lines", log_file, cnt))
end



local schemas = {}
schemas[new_log({new_task({download,perfherder,}),task_exit,})] = {"other_hfs+_TL","other_clang8-macosx-cross_TL","linux_cvsa_coverity","linux_nojit_SM","other_gn_TL","linux_r_SM","android_B_WR","other_clang8-android_TL","other_nasm_TW64","other_stackwalk_TM","other_rustc-dist_TL","other_clang-tidy_TM","other_cbindgen_TM","linux_mozjs-crate_SM","other_stackwalk_TL","other_wrench-deps_WR","other_sccache_TL","other_clang-dist_TL","linux_arm_SM","other_mingw-fxc2-x86_TMW","linux_tsan_SM","other_clang8_TL","linux_wrench_WR","other_clang_TM","linux_nu_SM","linux_pkg_SM","other_stackwalk_TW32","linux_p_SM","osx_B_WR","other_clang-x86_TMW","other_clang4.0_TL","other_cbindgen_TL","linux_format_clang","other_dsymutil_TL","other_tup_TL","linux_rust_SM","other_clang7_TL","other_gradle-dependencies_TL","other_sccache_TM","other_gn_TM","other_clang-x64_TMW","linux_f_SM","android_wrench_WR","linux_cgc_SM","other_sixgill_TL","other_cctools_TM","linux_infer_?","other_grcov_TM","other_rust-size_TL","linux_asan_SM","other_cctools_TL","other_clang-tidy_TL","linux_tidy_clang","linux_arm64_SM","other_mingw32-nsis_TMW","linux_msan_SM",}
schemas[new_log({new_task({new_mozharness({perfherder,upload,download,package_tests,}),perfherder,}),task_exit,})] = {"win_Bd_WMC32","android_BnoGPS_?","osx_Bof_?","linux_Bd_?","linux_BoR_?","win_Bo_WMC32","win_Bd_WMC64","linux_Bof_?","android_Bof_?","linux_Bo_?","linux_Bocf_?","osx_B_?","win_Bo_WMC64",}
schemas[new_log({new_task({perfherder,}),task_exit,})] = {"other_wine_TMW","other_rust-macos_TL","win_UV11_UV","other_W_?","osx_UgsB_?","android_Ugs_?","other_deb7-base_I","other_binutil_TL","win_UV13_UV","other_snap_I","other_mingw32-gcc_TMW","linux_UV4_UV","linux_ml_py2","osx_UV5_UV","linux_Sym_Bpgo","other_deb7-32-raw_I","other_deb9-pkg_I","other_Chromium_cron","win_UV8_UV","linux_release_py2","linux_Venv_?","linux_UV13_UV","other_nasm-2.13.02_TL","linux_UV8_UV","win_UV12_UV","other_rust-1.32_TL","other_infer_TL","other_wpt-meta_?","other_D_?","other_pip_I","osx_UV16_UV","other_node_TM","other_vb_I","other_webrender_I","other_rust-1.28_TW64","osx_UV10_UV","other_android-sdk-linux_TL","win_Ugs_?","win_UV10_UV","linux_rap_py2","linux_devtools_node","other_node_TL","other_deb9-raw_I","other_rust-1.31_TMW","linux_UV2_UV","osx_SymN_?","win_repack_Gd","linux_mch_py2","other_rust-macos-1.32_TL","osx_repack_Gd","osx_UV12_UV","osx_UV15_UV","other_pg_I","win_UV14_UV","osx_UV9_UV","other_rust-1.31_TL","other_deb7-32_I","other_shell_?","other_venv_I","linux_UV11_UV","other_custom-v8_I","osx_UV4_UV","osx_UV2_UV","other_node_TW32","linux_tidy_WR","win_UV16_UV","other_rt_AC","osx_UV14_UV","other_bl_?","other_f8_?","other_toolchain-arm64_I","other_node_TW64","win_Sym_?","other_deb7_I","other_promote_firefox_AC","linux_mb_py3","other_PY_?","linux_UV3_UV","other_deb7jsrs_I","other_fetch_I","osx_UV8_UV","other_libdmg-hfs+_TL","other_android-ndk-linux_TL","other_rust-1.34_TW64","win_UV15_UV","other_l1nt_?","linux_UV16_UV","linux_vcs_py3","osx_Sym_?","win_UV7_UV","other_rust-1.28_TL","linux_run_Bpgo","win_UV3_UV","other_custom-v8_TL","other_cAll_AC","other_Rel_cron","other_yaml_?","other_cx_AC","linux_UgsBg_?","linux_term_py3","osx_UV1_UV","linux_UV12_UV","other_Cvf_?","other_Doc_?","linux_mnh_py2","other_apk_I","win_UV1_UV","linux_Wm_?","other_gcc6_TL","other_Searchfox_cron","android_SymN_?","other_deb9-base_I","other_Nd-win64_cron","other_dt16t_I","other_rust-android_TL","other_ib_I","other_mingw_I","other_rust-macos-1.31_TL","win_UgsB_?","other_PR_I","other_Bugzilla_?","other_Nd_cron","linux_UV7_UV","other_customv8_cron","other_toolchain_I","other_diff_I","osx_UV3_UV","linux_UV5_UV","osx_Ugs_?","win_UV6_UV","linux_UV14_UV","other_lnt_I","other_rust_TMW","linux_term_py2","other_deb7-pkg_I","other_rr_AC","linux_mb_py2","other_rust_TL","linux_Symg_?","win_UgsBoR_?","other_deb7-raw_I","win_UV5_UV","other_Na_cron","linux_vcs_py2","win_UV4_UV","osx_Symg_?","linux_ref_py2","linux_try_py2","other_deb9_I","other_spell_?","other_deb7-32-pkg_I","other_uv_I","osx_UV11_UV","other_static-analysis-build_I","other_deb7-bb_I","other_idx_I","other_upx_TMW","other_file_I","linux_debugger_node","other_DocUp_?","other_DWE_?","other_tm_?","other_rust_TW64","linux_Sym_?","other_Nd-win32_cron","win_UV2_UV","linux_release_py3","linux_UV9_UV","linux_UV1_UV","other_py-compat_?","other_deb9-arm64_I","osx_UV13_UV","linux_repack_Gd","other_mingw_?","other_rmt_AC","other_raT_AC","linux_UgsB_?","other_ES_?","win_SymN_?","other_Bk_AC","osx_UV7_UV","osx_UV6_UV","linux_UgsBoR_?","other_agb_I","other_rust-1.34_TL","win_UV9_UV","other_add-new_AC","other_nasm_TL","linux_UV6_UV","osx_UgsBg_?","linux_Ugs_?","linux_tg_py2","linux_UV10_UV","linux_SymN_?","linux_UV15_UV",}
schemas[new_log({new_task({new_mozharness({test_ref,}),}),task_exit,})] = {"android_C4_R-1proc","android_R1_R","android_J83_R-1proc","android_R2_R-1proc","android_J89_R-1proc","android_R2_R","android_C9_R","android_R13_R","android_R26_R-1proc","android_R28_R","android_R50_R","android_R11_R-1proc","android_J77_R-1proc","android_J78_R-1proc","android_J98_R-1proc","android_R7_R","android_R9_R-1proc","android_R6_R","android_J70_R-1proc","android_R9_R","android_J65_R-1proc","android_J29_R-1proc","android_R18_R","android_C4_R","android_J27_R-1proc","android_R41_R","android_R34_R","android_R35_R","android_R42_R-1proc","android_R34_R-1proc","android_R51_R-1proc","android_R3_R","android_R3_R-1proc","android_J35_R-1proc","android_J56_R-1proc","android_J38_R-1proc","android_R48_R-1proc","android_J59_R-1proc","android_C_R","android_C10_R","android_C5_R","android_J88_R-1proc","android_R21_R-1proc","android_J95_R-1proc","android_J64_R-1proc","android_R26_R","android_J3_R","android_J19_R-1proc","android_R46_R-1proc","android_R1_R-1proc","android_C6_R","android_R35_R-1proc","android_R39_R-1proc","android_R54_R","android_J60_R-1proc","android_J86_R-1proc","android_J61_R-1proc","android_C5_R-1proc","android_R16_R","android_C7_R-1proc","android_R4_R","android_J63_R-1proc","android_J40_R-1proc","android_R38_R-1proc","android_J79_R-1proc","android_R16_R-1proc","android_C_R-e10s","android_J97_R-1proc","android_R17_R-1proc","android_R10_R","android_C8_R","android_R43_R-1proc","android_R56_R","android_J53_R-1proc","android_R47_R-1proc","android_J71_R-1proc","android_J26_R-1proc","android_C1_R-1proc","android_J23_R-1proc","android_R25_R-1proc","android_J81_R-1proc","android_J6_R","android_R8_R","android_J7_R","android_J74_R-1proc","android_R49_R","android_J48_R-1proc","android_R43_R","android_R24_R","android_R17_R","android_R40_R","android_J87_R-1proc","android_J33_R-1proc","android_J93_R-1proc","android_R15_R","android_J54_R-1proc","android_R23_R","android_R52_R","android_J100_R-1proc","android_R7_R-1proc","android_J67_R-1proc","android_J73_R-1proc","android_C2_R-1proc","android_J42_R-1proc","android_J32_R-1proc","android_J22_R-1proc","android_R45_R-1proc","android_J75_R-1proc","android_J49_R-1proc","android_J66_R-1proc","android_R28_R-1proc","android_R22_R-1proc","android_R49_R-1proc","android_R41_R-1proc","android_R33_R","android_R20_R-1proc","android_R27_R","android_R22_R","android_R10_R-1proc","android_R33_R-1proc","android_R53_R-1proc","android_R36_R-1proc","android_J69_R-1proc","android_J14_R-1proc","android_C1_R","android_J30_R-1proc","android_J20_R-1proc","android_C3_R","android_R52_R-1proc","android_R54_R-1proc","android_R6_R-1proc","android_J28_R-1proc","android_J94_R-1proc","android_R36_R","android_J8_R","android_J51_R-1proc","android_R39_R","android_J13_R-1proc","android_C8_R-1proc","android_R14_R-1proc","android_J44_R-1proc","android_C10_R-1proc","android_J2_R","android_J76_R-1proc","android_R29_R-1proc","android_J68_R-1proc","android_J92_R-1proc","android_J46_R-1proc","android_J47_R-1proc","android_R44_R","android_R20_R","android_R25_R","android_J24_R-1proc","android_R37_R-1proc","android_J62_R-1proc","android_R38_R","android_J45_R-1proc","android_R40_R-1proc","android_TV3_?","android_R55_R-1proc","android_C6_R-1proc","android_R27_R-1proc","android_R32_R","android_J31_R-1proc","android_C9_R-1proc","android_R46_R","android_J25_R-1proc","android_R18_R-1proc","android_J39_R-1proc","android_R50_R-1proc","android_R53_R","android_R5_R-1proc","android_R15_R-1proc","android_R11_R","android_R45_R","android_J43_R-1proc","android_R31_R-1proc","android_R30_R-1proc","android_R48_R","android_J52_R-1proc","android_R19_R","android_R24_R-1proc","android_R47_R","android_J50_R-1proc","android_R14_R","android_C7_R","android_R56_R-1proc","android_J57_R-1proc","android_R51_R","android_J15_R-1proc","android_R12_R-1proc","android_R5_R","android_R4_R-1proc","android_J82_R-1proc","android_J34_R-1proc","android_R31_R","android_J1_R","android_J55_R-1proc","android_J37_R-1proc","android_R21_R","android_J84_R-1proc","android_R29_R","android_R30_R","android_J21_R-1proc","android_J41_R-1proc","android_J36_R-1proc","android_J4_R","android_J72_R-1proc","android_R32_R-1proc","android_R42_R","android_J18_R-1proc","android_J17_R-1proc","android_J16_R-1proc","android_J90_R-1proc","android_C2_R","android_J5_R","android_C3_R-1proc","android_J85_R-1proc","android_J58_R-1proc","android_R19_R-1proc","android_J99_R-1proc","android_R8_R-1proc","android_J91_R-1proc","android_J80_R-1proc","android_R23_R-1proc","android_R55_R","android_R44_R-1proc","android_R13_R-1proc","android_R12_R","android_J96_R-1proc","android_R37_R",}
schemas[new_log({new_task({new_mozharness({test,}),}),})] = {"win_wpt11_W-e10s","win_wpt8_W-e10s","win_wpt17_W","win_Wd2_W-fis","osx_MnM_?","win_Wr4_W","osx_wpt12_W-fis","osx_Wd1_W","osx_Wd1_W-e10s","osx_wpt1_W-e10s","osx_en-US_Fxfn-r-e10s","win_wpt14_W-e10s","osx_wpt5_W","osx_Wr5_W-e10s","win_Wr2_W","osx_wpt8_W-fis","osx_Wd2_W","osx_wpt3_W-fis","osx_wpt9_W-e10s","osx_wpt13_W-fis","osx_wpt12_W","osx_Wd2_W-fis","win_wpt13_W","osx_wpt16_W-fis","win_en-US_Fxfn-l","win_wpt5_W-e10s","osx_wpt2_W-fis","win_wpt6_W","win_Wr5_W-e10s","osx_wpt9_W-fis","win_wpt3_W","osx_wpt7_W","osx_wpt10_W","osx_wpt3_W","win_wpt7_W","osx_Wr1_W-e10s","win_wpt10_W","osx_MnH_?","osx_wpt10_W-e10s","osx_wpt6_W-fis","osx_c_tt","win_Wr8_W","osx_Wr2_W","win_wpt8_W","win_Wr3_W","win_Wd1_W","win_Wr5_W","osx_wpt1_W","win_wpt10_W-e10s","win_Wr1_W-e10s","osx_wpt1_W-fis","osx_Wr4_W-e10s","win_Wr_W-e10s","win_wpt16_W","win_Wr6_W","osx_wpt14_W-fis","win_wpt2_W-e10s","osx_wpt5_W-e10s","osx_Wr2_W-e10s","osx_wpt13_W-e10s","win_wpt18_W-e10s","osx_wpt11_W-e10s","osx_Wr6_W","osx_wpt7_W-fis","win_wpt5_W","osx_en-US_Fxfn-l-e10s","osx_wpt4_W-e10s","win_wpt3_W-e10s","win_Wr4_W-e10s","osx_Wr2_W-fis","win_Wd1_W-e10s","win_Wr3_W-e10s","win_wpt4_W","osx_wpt13_W","win_MnM_?","osx_wpt11_W","osx_wpt15_W-e10s","osx_Wr1_W-fis","osx_wpt6_W-e10s","osx_Mn_?","win_Wd3_W","win_wpt18_W","osx_wpt5_W-fis","osx_wpt14_W","win_Mn_?","win_Wd2_W","osx_wpt9_W","osx_wpt8_W","win_wpt2_W","win_en-US_Fxfn-l-e10s","osx_wpt11_W-fis","win_Wd4_W","win_MnH_?","win_Wd1_W-fis","osx_Wr1_W","osx_Wr5_W-fis","osx_Wr4_W-fis","osx_wpt14_W-e10s","osx_wpt15_W-fis","osx_wpt3_W-e10s","osx_en-US_Fxfn-l","win_wpt16_W-e10s","osx_wpt4_W-fis","win_Wr7_W","osx_wpt12_W-e10s","win_TCw_?","osx_wpt8_W-e10s","osx_Wr_W-e10s","osx_wpt7_W-e10s","win_en-US_Fxfn-r-e10s","win_Wr2_W-e10s","win_wpt6_W-e10s","osx_Wr3_W-e10s","win_wpt12_W","osx_Wd2_W-e10s","osx_wpt2_W-e10s","win_wpt11_W","win_wpt15_W-e10s","osx_wpt6_W","win_en-US_Fxfn-r","win_wpt14_W","osx_Wr5_W","win_Wd2_W-e10s","win_wpt7_W-e10s","win_wpt9_W-e10s","win_c_tt","osx_Wr4_W","win_MnG_?","osx_wpt4_W","osx_Wr6_W-e10s","osx_Wr3_W","win_wpt15_W","osx_wpt2_W","osx_en-US_Fxfn-r","win_wpt13_W-e10s","osx_Wr6_W-fis","win_Wr1_W","osx_wpt15_W","win_wpt4_W-e10s","osx_Wr3_W-fis","osx_wpt16_W-e10s","win_wpt12_W-e10s","osx_wpt10_W-fis","osx_Wd1_W-fis","win_wpt17_W-e10s","osx_wpt16_W","win_wpt1_W","win_wpt1_W-e10s","win_wpt9_W","win_Wr6_W-e10s",}
schemas[new_log({new_task({new_mozharness({test,perfherder,}),}),task_exit,})] = {"linux_ab_SY-e10s","linux_ab-d_SY","linux_sy-tp6_SY","linux_ab_SY","linux_sy_SY-e10s","linux_sy_SY","linux_sy-d_SY","linux_sy_SYss",}
schemas[new_log({new_task({new_mozharness({download,perfherder,}),perfherder,}),task_exit,})] = {"linux_Bp_?","osx_N13_L10n","osx_N8_L10n","osx_N18_L10n","osx_L10n_?","osx_N11_L10n","linux_BR_?","osx_N14_L10n","osx_N5_L10n","osx_N2_L10n","osx_N19_L10n","osx_N12_L10n","osx_N17_L10n","osx_N3_L10n","osx_N10_L10n","osx_N16_L10n","osx_N6_L10n","osx_N4_L10n","osx_N1_L10n","osx_N15_L10n","osx_N20_L10n","osx_N7_L10n","android_L10n_?","osx_N9_L10n",}
schemas[new_log({new_task({new_mozharness({test_gtest,perfherder,}),perfherder,}),})] = {"win_GTest_?",}
schemas[new_log({new_task({new_mozharness({download,perfherder,}),perfherder,}),})] = {"win_N9_L10n","win_N20_L10n","win_N7_L10n","win_Bp_?","win_N14_L10n","win_N4_L10n","win_L10n_?","win_N10_L10n","win_N11_L10n","win_N3_L10n","win_N12_L10n","win_N13_L10n","win_N5_L10n","win_N8_L10n","win_N2_L10n","win_N17_L10n","win_N1_L10n","win_N15_L10n","win_N16_L10n","win_BR_?","win_N18_L10n","win_N6_L10n","win_N19_L10n",}
schemas[new_log({new_task({new_mozharness({test_ref,}),perfherder,}),task_exit,})] = {"linux_Ru8_R-sw","linux_Ru1_R-sw","linux_R7_R-e10s","linux_R5_R-1proc","linux_J4_R-sw","linux_Ru1_R","linux_Ru8_R","linux_R8_R-e10s","linux_R7_R","linux_Ru4_R-fis","linux_J3_R-fis","linux_R4_R-sw","linux_Ru7_R-e10s","linux_Ru6_R","linux_R1_R-fis","linux_R3_R-e10s","linux_R8_R-1proc","linux_Ru5_R-fis","linux_R5_R-sw","linux_R3_R-fis","linux_Ru6_R-fis","linux_Ru2_R-fis","linux_Ru5_R","linux_C_R-1proc","linux_J3_R-sw","linux_R8_R","linux_R4_R","linux_Ru1_R-e10s","linux_Ru5_R-sw","linux_Ru7_R","linux_R2_R-1proc","linux_Ru6_R-e10s","linux_R5_R","linux_C_R-e10s","linux_J5_R-fis","linux_Ru3_R-sw","linux_J5_R","linux_Ru7_R-sw","linux_Ru7_R-fis","linux_R2_R","linux_R1_R-1proc","linux_Ru8_R-e10s","linux_C_R-fis","linux_J2_R-sw","linux_Ru3_R-e10s","linux_R3_R-1proc","linux_Ru5_R-e10s","linux_R5_R-fis","linux_C_R-sw","linux_R8_R-sw","linux_Ru1_R-fis","linux_J2_R-fis","linux_R2_R-fis","linux_R3_R","linux_Ru8_R-fis","linux_R7_R-fis","linux_J1_R","linux_R6_R-e10s","linux_Ru4_R","linux_Ru2_R-e10s","linux_J4_R-fis","linux_Ru2_R-sw","linux_C_R","linux_Ru6_R-sw","linux_R6_R-fis","linux_J3_R","linux_R1_R-sw","linux_R4_R-fis","linux_R7_R-1proc","linux_R6_R-sw","linux_R8_R-fis","linux_R6_R-1proc","linux_J1_R-fis","linux_R1_R-e10s","linux_R6_R","linux_Ru4_R-e10s","linux_R2_R-e10s","linux_Ru3_R","linux_R7_R-sw","linux_J4_R","linux_R4_R-1proc","linux_R5_R-e10s","linux_R3_R-sw","linux_J1_R-sw","linux_J5_R-sw","linux_Ru3_R-fis","linux_R2_R-sw","linux_R1_R","linux_Ru2_R","linux_Ru4_R-sw","linux_J2_R","linux_R4_R-e10s",}
schemas[new_log({new_task({new_mozharness({test,gecko,}),perfherder,}),task_exit,})] = {"linux_10_M-1proc","linux_gpu_M-1proc","linux_gl1c_M-e10s","linux_h1_M","linux_bc8_M-fis","linux_gpu_M","linux_gl1c_M-1proc","linux_dt13_M-e10s","linux_3_M-e10s","linux_dt6_M-e10s","linux_dt11_M-sw","linux_mda1_M","linux_dt12_M-e10s","linux_dt6_M-fis","linux_4_M-fis","linux_dt4_M-sw","linux_mda3_M-sw","linux_bc13_M-sw","linux_bc5_M-e10s","linux_5_M-sw","linux_4_M-sw","linux_bc15_M-sw","linux_8_M-e10s","linux_dt14_M-e10s","linux_bc5_M-fis","linux_bc10_M-fis","linux_dt7_M-fis","linux_bc15_M-e10s","linux_dt4_M-e10s","linux_dt15_M","linux_7_M-e10s","linux_bc6_M","linux_mda2_M-spi","linux_mda2_M-fis","linux_6_M-e10s","linux_h6_M-e10s","linux_bc9_M","linux_cl_M-e10s","linux_dt7_M","linux_bc4_M-sw","linux_h8_M-e10s","linux_bc1_M","linux_7_M","linux_2_M-fis","linux_bc3_M-sw","linux_bc6_M-e10s","linux_bc7_M","linux_13_M-fis","linux_2_M-sw","linux_dt8_M","linux_gl1e_M","linux_bc16_M-fis","linux_dt11_M","linux_5_M-e10s","linux_bc12_M-sw","linux_bc12_M-e10s","linux_15_M-e10s","linux_mda3_M-e10s","linux_h3_M","linux_bc7_M-sw","linux_h12_M-e10s","linux_a11y_M-1proc","linux_13_M","linux_bc1_M-sw","linux_10_M-fis","linux_dt9_M-e10s","linux_a11y_M","linux_h5_M-e10s","linux_h16_M-e10s","linux_16_M-1proc","linux_9_M","linux_c3_M-1proc","linux_bc8_M-e10s","linux_mda1_M-fis","linux_dt5_M-sw","linux_dt5_M-fis","linux_h4_M","linux_bc4_M-fis","linux_bc2_M-e10s","linux_dt8_M-e10s","linux_6_M-fis","linux_dt6_M-sw","linux_dt10_M","linux_bc12_M","linux_6_M","linux_mda2_M-e10s-spi","linux_dt2_M-sw","linux_1_M","linux_5_M-1proc","linux_gl2_M","linux_bc14_M-fis","linux_mda3_M-spi","linux_4_M","linux_12_M-e10s","linux_1_M-fis","linux_bc3_M-fis","linux_bc5_M","linux_bc5_M-sw","linux_14_M-e10s","linux_TV_?","linux_h11_M-e10s","linux_c1_M","linux_bc3_M","linux_6_M-sw","linux_h9_M-e10s","linux_h1_M-e10s","linux_bc10_M-sw","linux_15_M-1proc","linux_dt12_M-fis","linux_1_M-1proc","linux_bc7_M-fis","linux_mda1_M-e10s-spi","linux_mda2_M-sw","linux_cl_M","linux_c2_M-sw-1proc","linux_14_M-fis","linux_gl2_M-e10s","linux_gl1c_M-fis","linux_h2_M","linux_9_M-1proc","linux_11_M","linux_12_M-1proc","linux_dt14_M","linux_mda3_M-e10s-spi","linux_3_M-fis","linux_dt1_M","linux_gl1e_M-sw","linux_h5_M","linux_dt16_M-e10s","linux_gpu_M-sw","linux_8_M-1proc","linux_14_M-sw","linux_5_M","linux_7_M-fis","linux_2_M","linux_bc7_M-e10s","linux_bc6_M-fis","linux_dt11_M-fis","linux_bc15_M-fis","linux_dt3_M-e10s","linux_h7_M-e10s","linux_dt9_M-fis","linux_bc11_M-fis","linux_h14_M-e10s","linux_gpu_M-e10s","linux_c1_M-sw-1proc","linux_mda1_M-sw","linux_10_M","linux_c1_M-1proc","linux_11_M-1proc","linux_TC1_?","linux_4_M-e10s","linux_3_M-1proc","linux_gl1e_M-e10s","linux_9_M-fis","linux_bc14_M","linux_dt1_M-fis","linux_mda3_M","linux_12_M-fis","linux_dt12_M-sw","linux_TV2_?","linux_13_M-e10s","linux_dt11_M-e10s","linux_dt6_M","linux_bc4_M-e10s","linux_c2_M-1proc","linux_bc6_M-sw","linux_bc10_M","linux_h2_M-fis","linux_bc9_M-sw","linux_10_M-e10s","linux_c3_M-sw-1proc","linux_dt7_M-e10s","linux_bc9_M-e10s","linux_bc1_M-e10s","linux_dt8_M-fis","linux_dt3_M","linux_h2_M-e10s","linux_TV1_?","linux_bc10_M-e10s","linux_bc2_M-sw","linux_dt10_M-e10s","linux_bc2_M","linux_gl3_M-e10s","linux_7_M-sw","linux_16_M-fis","linux_gl1c_M-sw","linux_16_M","linux_10_M-sw","linux_2_M-e10s","linux_h13_M-e10s","linux_dt7_M-sw","linux_bc12_M-fis","linux_bc3_M-e10s","linux_dt9_M-sw","linux_11_M-fis","linux_h10_M-e10s","linux_13_M-sw","linux_bc2_M-fis","linux_mda1_M-spi","linux_h4_M-e10s","linux_gl1c_M","linux_1_M-sw","linux_7_M-1proc","linux_15_M-sw","linux_ss_M","linux_dt5_M-e10s","linux_bc13_M-e10s","linux_15_M","linux_dt15_M-e10s","linux_8_M-sw","linux_bc8_M-sw","linux_3_M-sw","linux_dt12_M","linux_dt3_M-sw","linux_bc15_M","linux_bc8_M","linux_14_M-1proc","linux_dt1_M-e10s","linux_h4_M-fis","linux_bct_M","linux_bc16_M","linux_9_M-sw","linux_mda1_M-e10s","linux_1_M-e10s","linux_c2_M","linux_mda3_M-fis","linux_gpu_M-fis","linux_2_M-1proc","linux_TC3_?","linux_bc11_M-e10s","linux_bc11_M-sw","linux_11_M-sw","linux_13_M-1proc","linux_12_M","linux_3_M","linux_12_M-sw","linux_14_M","linux_bc14_M-e10s","linux_9_M-e10s","linux_a11y_M-sw-1proc","linux_dt2_M-e10s","linux_dt8_M-sw","linux_bc14_M-sw","linux_ss_M-fis","linux_h1_M-fis","linux_dt5_M","linux_8_M","linux_gl3_M","linux_bc1_M-fis","linux_bc16_M-e10s","linux_h15_M-e10s","linux_dt2_M-fis","linux_c3_M","linux_11_M-e10s","linux_8_M-fis","linux_h3_M-e10s","linux_dt10_M-fis","linux_bc11_M","linux_bc4_M","linux_dt16_M","linux_bc13_M-fis","linux_gl1_M-e10s","linux_bc16_M-sw","linux_gl1e_M-fis","linux_dt13_M","linux_gl1_M","linux_dt9_M","linux_6_M-1proc","linux_bc13_M","linux_16_M-sw","linux_mda2_M-e10s","linux_dt4_M-fis","linux_mda2_M","linux_4_M-1proc","linux_dt10_M-sw","linux_16_M-e10s","linux_dt1_M-sw",}
schemas[new_log({new_task({new_mozharness({test,gecko,task_exit,}),}),})] = {"linux_h3_M-fis","linux_15_M-fis","linux_5_M-fis","linux_bc9_M-fis","linux_h5_M-fis",}
schemas[new_log({new_task({new_mozharness({perfherder,download,}),perfherder,}),task_exit,})] = {"win_Bo_WM64","android_gv-docs_A","android_apilint_A","win_Bd_WM64","win_Bo_WM32","linux_S_?","android_checkstyle_A","android_lint_A","android_findbugs_A","android_test_A","win_Bd_WM32",}
schemas[new_log({new_task({new_mozharness({test_ref,}),perfherder,}),})] = {"win_Rg3_R-fis","osx_R6_R-fis","win_Rg1_R-e10s","osx_R1_R-fis","osx_C_R-fis","win_Ru4_R-fis","win_R3_R","win_R1_R-fis","win_C_R-fis","win_Rg2_R-e10s","win_J2_R","osx_R1_R","osx_R5_R","win_R1_R","win_R4_R-fis","osx_R4_R","osx_J2_R","osx_R8_R","win_Ru1_R-fis","win_J3_R","osx_R3_R-e10s","win_Rg2_R-fis","osx_R2_R","win_J1_R","win_J4_R","win_Ru2_R-fis","osx_R3_R-fis","win_Ru2_R","win_Rg2_R","win_Ru3_R-e10s","win_R3_R-e10s","win_R3_R-fis","win_R4_R","win_R4_R-e10s","win_R1_R-e10s","win_Ru1_R","win_Ru4_R","osx_R8_R-fis","osx_R5_R-fis","osx_R6_R","win_R2_R-fis","win_Rg4_R","osx_C_R-e10s","win_Rg1_R-fis","osx_R2_R-e10s","win_Ru1_R-e10s","win_Ru3_R-fis","osx_R2_R-fis","win_R5_R","win_R6_R","win_R2_R-e10s","win_Rg3_R","win_R2_R","win_Rg4_R-e10s","osx_J1_R","win_C_R-e10s","osx_J3_R","win_C_R","osx_R3_R","osx_R7_R-fis","osx_C_R","win_Rg3_R-e10s","win_Ru2_R-e10s","win_J1_R-fis","win_J2_R-fis","win_J5_R","win_Rg1_R","win_Rg4_R-fis","win_Ru4_R-e10s","win_Ru3_R","osx_R4_R-fis","osx_R1_R-e10s","osx_R7_R",}
schemas[new_log({new_task({new_mozharness({perfherder,}),perfherder,}),task_exit,})] = {"linux_N20_L10n","linux_N3_L10n","linux_N2_L10n","linux_N9_L10n","linux_N4_L10n","linux_N15_L10n","linux_N6_L10n","linux_N13_L10n","linux_N16_L10n","linux_N14_L10n","linux_N12_L10n","linux_N1_L10n","linux_N18_L10n","linux_N8_L10n","linux_L10n_?","linux_N17_L10n","linux_N10_L10n","linux_N5_L10n","linux_N19_L10n","linux_N11_L10n","linux_N7_L10n",}
schemas[new_log({new_task({new_mozharness({}),perfherder,}),task_exit,})] = {"linux_mk_L10n-Rpk","linux_my_L10n-Rpk","linux_Jit2_?","linux_ff_L10n-Rpk","linux_sq_L10n-Rpk","linux_hi-IN_L10n-Rpk","linux_zh-CN_L10n-Rpk","linux_mr_L10n-Rpk","linux_ka_L10n-Rpk","other_Src_?","linux_ar_L10n-Rpk","linux_ru_L10n-Rpk","linux_wo_L10n-Rpk","linux_sv-SE_L10n-Rpk","linux_is_L10n-Rpk","linux_rm_L10n-Rpk","linux_oc_L10n-Rpk","linux_da_L10n-Rpk","linux_ltg_L10n-Rpk","linux_ca_L10n-Rpk","linux_TC_?","linux_bg_L10n-Rpk","linux_UVC_?","linux_Rpk_?","linux_Jit1_?","linux_te_L10n-Rpk","linux_cs_L10n-Rpk","linux_gu-IN_L10n-Rpk","linux_km_L10n-Rpk","linux_Jit6_?","linux_Nr_?","linux_pl_L10n-Rpk","linux_eo_L10n-Rpk","linux_fy-NL_L10n-Rpk","linux_ms_L10n-Rpk","linux_en-CA_L10n-Rpk","linux_be_L10n-Rpk","linux_th_L10n-Rpk","linux_mh_py2","linux_bn_L10n-Rpk","linux_sl_L10n-Rpk","linux_lij_L10n-Rpk","linux_he_L10n-Rpk","linux_nn-NO_L10n-Rpk","linux_gn_L10n-Rpk","linux_Z5_Z","osx_UVC_?","linux_ga-IE_L10n-Rpk","linux__tt-c-e10s","linux_TVg_?","linux_nb-NO_L10n-Rpk","linux_ach_L10n-Rpk","linux_pt-BR_L10n-Rpk","linux_kk_L10n-Rpk","win_UVC_?","linux_en-GB_L10n-Rpk","linux_ur_L10n-Rpk","linux_hu_L10n-Rpk","linux_ko_L10n-Rpk","linux_hsb_L10n-Rpk","linux_xh_L10n-Rpk","linux_ast_L10n-Rpk","linux_Z6_Z","linux_dsb_L10n-Rpk","linux_az_L10n-Rpk","linux_it_L10n-Rpk","linux_el_L10n-Rpk","linux_eu_L10n-Rpk","linux_zh-TW_L10n-Rpk","linux_hr_L10n-Rpk","linux_es-AR_L10n-Rpk","linux_br_L10n-Rpk","linux_pa-IN_L10n-Rpk","linux_Z4_Z","linux_gl_L10n-Rpk","linux_trs_L10n-Rpk","linux_tr_L10n-Rpk","linux_cak_L10n-Rpk","linux_hy-AM_L10n-Rpk","other_GenChcks_Rel","linux_lo_L10n-Rpk","linux_an_L10n-Rpk","linux_fa_L10n-Rpk","linux_es-MX_L10n-Rpk","linux_tl_L10n-Rpk","linux_Z1_Z","linux_gd_L10n-Rpk","linux_uk_L10n-Rpk","linux_nl_L10n-Rpk","linux_et_L10n-Rpk","linux_ta_L10n-Rpk","linux_ja_L10n-Rpk","linux_af_L10n-Rpk","linux_Jit5_?","linux_lt_L10n-Rpk","linux_fi_L10n-Rpk","linux_bs_L10n-Rpk","linux_Z8_Z","linux_Jit3_?","linux_es-CL_L10n-Rpk","linux_son_L10n-Rpk","linux_kn_L10n-Rpk","linux_ro_L10n-Rpk","linux_Z2_Z","linux_kab_L10n-Rpk","linux_vi_L10n-Rpk","linux_sk_L10n-Rpk","linux_Z3_Z","linux_cy_L10n-Rpk","linux_crh_L10n-Rpk","linux_fr_L10n-Rpk","linux_ia_L10n-Rpk","linux_si_L10n-Rpk","linux_es-ES_L10n-Rpk","linux_de_L10n-Rpk","linux_Jit4_?","linux_Z7_Z","other_ckbouncer_Rel","linux_sr_L10n-Rpk","linux_pt-PT_L10n-Rpk","linux_lv_L10n-Rpk","linux_ne-NP_L10n-Rpk","linux_id_L10n-Rpk","linux_uz_L10n-Rpk",}
schemas[new_log({new_task({new_mozharness({download,}),perfherder,}),})] = {"win_es-ES_MSI","win_it_MSI","win_fa_L10n-Rpk","win_bn_MSI","win_ka_L10n-Rpk","win_lo_MSI","win_trs_L10n-Rpk","win_lv_MSI","win_th_MSI","win_ms_L10n-Rpk","win_ru_L10n-Rpk","win_is_MSI","win_bg_MSI","win_id_MSI","win_zh-TW_L10n-Rpk","win_si_MSI","win_bg_L10n-Rpk","win_ne-NP_L10n-Rpk","win_crh_MSI","win_pt-BR_L10n-Rpk","win_Rpk_?","win_ne-NP_MSI","win_zh-CN_L10n-Rpk","win_sk_MSI","win_cs_MSI","win_fy-NL_MSI","win_dsb_L10n-Rpk","win_hu_L10n-Rpk","win_ur_L10n-Rpk","win_sl_L10n-Rpk","win_cy_L10n-Rpk","win_hu_MSI","win_ro_L10n-Rpk","win_es-ES_L10n-Rpk","win_fa_MSI","win_de_MSI","win_hy-AM_L10n-Rpk","win_eu_MSI","win_mk_L10n-Rpk","win_km_L10n-Rpk","win_kn_L10n-Rpk","win_an_L10n-Rpk","win_et_MSI","win_bs_MSI","win_rm_MSI","win_Nr_?","win_az_L10n-Rpk","win_el_L10n-Rpk","win_dsb_MSI","win_kab_L10n-Rpk","win_eu_L10n-Rpk","win_ko_MSI","win_tr_L10n-Rpk","win_pt-BR_MSI","win_ta_MSI","win_sq_MSI","win_sr_L10n-Rpk","win_cak_MSI","win_nb-NO_MSI","win_gu-IN_L10n-Rpk","win_ca_L10n-Rpk","win_et_L10n-Rpk","win_wo_MSI","win_tr_MSI","win_gn_MSI","win_es-AR_MSI","win_sv-SE_MSI","win_da_MSI","win_trs_MSI","win_en-CA_MSI","win_my_L10n-Rpk","win_is_L10n-Rpk","win_cs_L10n-Rpk","win_an_MSI","win_sv-SE_L10n-Rpk","win_kk_MSI","win_vi_L10n-Rpk","win_ar_L10n-Rpk","win_hi-IN_L10n-Rpk","win_eo_MSI","win_ga-IE_MSI","win_fy-NL_L10n-Rpk","win_ltg_L10n-Rpk","win_es-AR_L10n-Rpk","win_lt_MSI","win_el_MSI","win_oc_MSI","win_sq_L10n-Rpk","win_pl_L10n-Rpk","win_uk_MSI","win_lv_L10n-Rpk","win_pt-PT_MSI","win_zh-CN_MSI","win_en-CA_L10n-Rpk","win_cy_MSI","win_pa-IN_MSI","win_br_L10n-Rpk","win_be_L10n-Rpk","win_zh-TW_MSI","win_lij_MSI","win_pl_MSI","win_ms_MSI","win_az_MSI","win_he_MSI","win_fr_L10n-Rpk","win_ga-IE_L10n-Rpk","win_af_L10n-Rpk","win_sk_L10n-Rpk","win_te_MSI","win_de_L10n-Rpk","win_fi_MSI","win_Sa_?","win_ja_L10n-Rpk","win_son_L10n-Rpk","win_ach_MSI","win_bn_L10n-Rpk","win_pa-IN_L10n-Rpk","win_en-GB_L10n-Rpk","win_xh_L10n-Rpk","win_te_L10n-Rpk","win_cak_L10n-Rpk","win_sl_MSI","win_ast_MSI","win_da_L10n-Rpk","win_nn-NO_MSI","win_gu-IN_MSI","win_ff_MSI","win_N_MSI","win_hsb_MSI","win_kab_MSI","win_ia_MSI","win_es-MX_L10n-Rpk","win_fr_MSI","win_vi_MSI","win_gd_L10n-Rpk","win_ach_L10n-Rpk","win_es-MX_MSI","win_af_MSI","win_ur_MSI","win_es-CL_MSI","win_he_L10n-Rpk","win_fi_L10n-Rpk","win_hi-IN_MSI","win_hr_L10n-Rpk","win_lt_L10n-Rpk","win_ia_L10n-Rpk","win_id_L10n-Rpk","win_oc_L10n-Rpk","win_ast_L10n-Rpk","win_br_MSI","win_kk_L10n-Rpk","win_tl_L10n-Rpk","win_km_MSI","win_kn_MSI","win_gl_MSI","win_ja_MSI","win_eo_L10n-Rpk","win_ff_L10n-Rpk","win_hsb_L10n-Rpk","win_uk_L10n-Rpk","win_uz_L10n-Rpk","win_lij_L10n-Rpk","win_ko_L10n-Rpk","win_hr_MSI","win_gl_L10n-Rpk","win_es-CL_L10n-Rpk","win_tl_MSI","win_sr_MSI","win_mr_MSI","win_th_L10n-Rpk","win_nl_MSI","win_bs_L10n-Rpk","win_nn-NO_L10n-Rpk","win_ta_L10n-Rpk","win_uz_MSI","win_nb-NO_L10n-Rpk","win_en-GB_MSI","win_son_MSI","win_my_MSI","win_si_L10n-Rpk","win_gd_MSI","win_ltg_MSI","win_hy-AM_MSI","win_be_MSI","win_ka_MSI","win_gn_L10n-Rpk","win_pt-PT_L10n-Rpk","win_lo_L10n-Rpk","win_rm_L10n-Rpk","win_ru_MSI","win_mr_L10n-Rpk","win_ro_MSI","win_it_L10n-Rpk","win_crh_L10n-Rpk","win_wo_L10n-Rpk","win_ca_MSI","win_ar_MSI","win_mk_MSI","win_nl_L10n-Rpk","win_xh_MSI",}
schemas[new_log({new_task({}),})] = {"win_SDR_?","win_Tools_?","other_Certs_?","win_NoPCLMUL_Cipher","win_MPI_?","other_sharedb_SSL","other_WPT-1_?","win_Lowhash_?","other_WPT-2_?","win_NoAESNI_Cipher","other_Nightly_?","win_Chains_?","osx_mb_py3","other_WPT-6+_?","other_standard_SSL","other_EC_?","win_EC_?","other_NoAVX_Cipher","other_Gtest_?","win_NoSSSE3|NEON_Cipher","win_pkix_SSL","osx_cargotest_WR","win_NoAVX_Cipher","other_B_?","other_MPI_?","win_Gtest_?","win_SMIME_?","win_Tests-F_FIPS","android_Dev build (macOS)_?","other_Unit_?","other_upgradedb_SSL","other_WPT-5_?","win_upgradedb_SSL","other_NoPCLMUL_Cipher","win_sharedb_SSL","other_NoAESNI_Cipher","win_Certs-F_FIPS","osx_mb_py2","win_standard_SSL","other_Merge_?","other_NoSSSE3|NEON_Cipher","win_B_FIPS","other_WPT-3_?","win_B_?","win_Merge_?","other_WPT-4_?","win_Nightly_?","win_DB_?","win_CRMF_?","win_Policy_?","other_Dev_?","osx_ml_py2","win_Dev build_?","osx_wrench_WR","win_Unit_?","win_Default_Cipher","other_Release_?","win_Certs_?",}
schemas[new_log({new_task({new_mozharness({gecko,}),perfherder,}),task_exit,})] = {"linux_6_M-V-1proc","linux_24_M-V-1proc","linux_27_M-V-1proc","linux_38_M-V-1proc","linux_1_M-V-1proc","linux_28_M-V-1proc","linux_34_M-V-1proc","linux_9_M-V-1proc","linux_3_M-V-1proc","linux_32_M-V-1proc","linux_26_M-V-1proc","linux_10_M-V-1proc","linux_15_M-V-1proc","linux_19_M-V-1proc","linux_37_M-V-1proc","linux_7_M-V-1proc","linux_21_M-V-1proc","linux_30_M-V-1proc","linux_17_M-V-1proc","linux_22_M-V-1proc","linux_39_M-V-1proc","linux_5_M-V-1proc","linux_25_M-V-1proc","linux_4_M-V-1proc","linux_29_M-V-1proc","linux_12_M-V-1proc","linux_11_M-V-1proc","linux_40_M-V-1proc","linux_13_M-V-1proc","linux_2_M-V-1proc","linux_35_M-V-1proc","linux_33_M-V-1proc","linux_31_M-V-1proc","linux_14_M-V-1proc","linux_18_M-V-1proc","linux_16_M-V-1proc","linux_8_M-V-1proc","linux_20_M-V-1proc","linux_36_M-V-1proc","linux_23_M-V-1proc",}
schemas[new_log({new_task({hazard_build,download,hazard_gen,perfherder,}),task_exit,})] = {"linux_H_SM","linux_H_?",}
schemas[new_log({new_task({new_mozharness({package_tests,upload,download,perfherder,}),perfherder,}),})] = {"win_Nn_?","win_Bf_?",}
schemas[new_log({new_task({new_mozharness({test,gecko,test_ref,}),perfherder,}),})] = {"win_TC2_?","win_TV3_?",}
schemas[new_log({new_task({new_mozharness({test,gecko,perfherder,}),perfherder,}),task_exit,})] = {"linux_dt2_M","linux_dt4_M","linux_dt3_M-fis",}
schemas[new_log({new_task({new_mozharness({test_gtest,}),perfherder,}),})] = {"osx_GTest_?",}
schemas[new_log({new_task({new_mozharness({test,}),}),task_exit,})] = {"linux_wpt4_W-fis","android_wpt9_W","linux_wpt8_W-fis","android_wpt16_W","android_X4_X","linux_Wr6_W-e10s","android_Wr2_W-1proc","android_gv-junit8_?","android_X8_X-1proc","android_X10_X-1proc","linux_wpt12_W-1proc","linux_wpt18_W-sw","android_gv-junit6_?","linux_Wd1_W","linux_Wr3_W-sw","linux_Wr2_W","linux_wpt18_W","linux_wpt11_W-e10s","android_gv-junit1_?","linux_Wd1_W-e10s","linux_wpt10_W-1proc","android_wpt11_W","linux_wpt4_W-1proc","android_wpt10_W-1proc","android_wpt15_W","linux_wpt1_W-1proc","android_Wr5_W","linux_MnH_?","android_X6_X-1proc","linux_Wd3_W","android_wpt18_W-1proc","android_Cpp_?","linux_en-US_Fxfn-r","linux_wpt1_W-e10s","android_X12_X-1proc","linux_wpt14_W-1proc","android_Wr3_W","linux_wpt12_W","android_wpt8_W","linux_wpt1_W-fis","linux_wpt6_W-fis","android_Wr6_W","linux_wpt12_W-e10s","android_X11_X","android_gv-junit4_?","android_X1_X","android_rc4_M-1proc","linux_wpt2_W-fis","linux_Wr2_W-fis","android_wpt17_W","android_wpt8_W-1proc","android_wpt1_W","android_X7_X-1proc","linux_Wr6_W-fis","linux_Wr8_W","android_wpt2_W-1proc","linux_wpt11_W-sw","linux_wpt1_W-sw","android_rc1_M-1proc","linux_wpt11_W","linux_wpt11_W-fis","linux_Wr1_W-1proc","linux_wpt13_W-sw","linux_wpt5_W-sw","linux_wpt4_W-sw","linux_en-US_Fxfn-l-e10s","linux_Wr4_W-1proc","android_Wr1_W-1proc","android_Wr5_W-1proc","linux_wpt10_W-fis","linux_wpt8_W-1proc","linux_wpt8_W-e10s","linux_wpt7_W-sw","linux_wpt4_W-e10s","linux_wpt3_W","linux_wpt10_W-e10s","linux_Wr2_W-1proc","linux_wpt6_W-e10s","linux_Wr1_W-sw","android_wpt4_W-1proc","linux_wpt2_W-1proc","linux_wpt15_W-fis","android_Mn_?","android_wpt14_W","linux_wpt12_W-sw","android_wpt9_W-1proc","linux_wpt15_W","linux_Wr5_W-fis","android_rc3_M","linux_wpt3_W-sw","linux_wpt14_W","linux_wpt13_W","android_X8_X","linux_wpt14_W-e10s","linux_wpt9_W-e10s","linux_wpt7_W-fis","linux_wpt8_W-sw","linux_wpt18_W-1proc","android_X2_X","linux_wpt13_W-1proc","android_X7_X","android_wpt12_W","android_wpt17_W-1proc","linux_wpt3_W-1proc","linux_wpt9_W-1proc","android_X12_X","android_X5_X-1proc","linux_wpt5_W-fis","android_wpt6_W","linux_wpt15_W-1proc","android_wpt16_W-1proc","android_gv-junit3_?","linux_wpt4_W","android_gv-junit_?","android_X5_X","android_gv-junit2_?","android_Wr4_W-1proc","linux_wpt9_W-fis","linux_wpt9_W","linux_wpt6_W-1proc","linux_wpt1_W","linux_Wd2_W-e10s","android_rc3_M-1proc","android_wpt3_W-1proc","linux_wpt6_W-sw","linux_Wr6_W","linux_Wr3_W","linux_Mn_?","linux_en-US_Fxfn-r-e10s","linux_wpt2_W-e10s","android_X9_X","linux_wpt3_W-e10s","linux_c_tt-e10s","android_X1_X-1proc","linux_wpt16_W-sw","android_X2_X-1proc","android_wpt2_W","linux_Wr4_W-e10s","linux_Wr5_W","linux_wpt16_W","linux_wpt16_W-1proc","android_rc1_M","android_rc2_M-1proc","linux_wpt5_W","android_wpt7_W","linux_wpt15_W-sw","android_wpt7_W-1proc","linux_wpt17_W-1proc","linux_wpt17_W","linux_Wr4_W-fis","linux_Wd2_W-sw","linux_Wd2_W","linux_Wr7_W","android_wpt6_W-1proc","android_Wr2_W","android_wpt11_W-1proc","linux_Wr2_W-sw","linux_wpt16_W-fis","linux_Wd_W-e10s","linux_Wr3_W-1proc","linux_Wr1_W","linux_c_tt","linux_wpt18_W-fis","linux_wpt7_W-1proc","android_wpt1_W-1proc","android_X9_X-1proc","linux_wpt16_W-e10s","android_wpt14_W-1proc","linux_wpt13_W-e10s","linux_Wd1_W-sw","android_Wr3_W-1proc","android_X6_X","android_X10_X","linux_wpt6_W","android_wpt13_W","linux_Wr4_W-sw","android_wpt18_W","android_wpt5_W","linux_Wd2_W-fis","android_X3_X-1proc","linux_Wd1_W-fis","linux_wpt5_W-1proc","linux_wpt9_W-sw","linux_wpt14_W-sw","linux_wpt10_W","android_X3_X","android_rc2_M","android_Wr6_W-1proc","linux_en-US_Fxfn-l","linux_wpt2_W","linux_wpt17_W-e10s","android_gv-junit5_?","linux_wpt14_W-fis","android_Wr1_W","linux_Wr2_W-e10s","linux_wpt10_W-sw","android_wpt12_W-1proc","android_wpt4_W","android_X11_X-1proc","linux_wpt15_W-e10s","android_X4_X-1proc","linux_wpt7_W","linux_wpt5_W-e10s","linux_TCw_?","android_wpt13_W-1proc","android_wpt3_W","linux_wpt3_W-fis","linux_wpt7_W-e10s","linux_MnM_?","android_wpt5_W-1proc","linux_Wr3_W-fis","linux_wpt17_W-fis","android_wpt10_W","android_wpt15_W-1proc","linux_Wr1_W-e10s","linux_Wr1_W-fis","android_rc4_M","linux_wpt13_W-fis","linux_wpt18_W-e10s","linux_wpt12_W-fis","linux_Wd4_W","linux_Wr5_W-e10s","android_gv-junit7_?","linux_wpt8_W","android_Wr4_W","linux_wpt17_W-sw","linux_wpt11_W-1proc","linux_Wr4_W","linux_Wr3_W-e10s","linux_wpt2_W-sw",}
schemas[new_log({new_task({new_mozharness({test,}),perfherder,}),})] = {"osx_X2_X","win_X5_X","osx_X1_X","win_X1_X-fis","win_Cpp_?","win_X4_X","osx_X1_X-fis","win_X_X","osx_X5_X","win_X1_X","osx_X2_X-fis","osx_X5_X-fis","win_X2_X","win_X2_X-fis","osx_X4_X","osx_X3_X","win_X6_X","osx_X_X","win_X3_X","osx_X3_X-fis","osx_Cpp_?","osx_X4_X-fis",}
schemas[new_log({new_task({perfherder,}),})] = {"win_ml_py2","win_mnh_py2","linux_webtool_js-bench-v8","win_rap_py2","linux_6speed_js-bench-v8","win_mb_py2","win_try_py2","linux_6speed_js-bench-sm","linux_ares6_js-bench-sm","linux_octane_js-bench-v8","linux_ares6_js-bench-v8","linux_webtool_js-bench-sm","win_term_py2","linux_sunspider_js-bench-sm","win_mb_py3","linux_octane_js-bench-sm",}
schemas[new_log({new_task({new_mozharness({test_gtest,}),}),task_exit,})] = {"android_GTest_?",}
schemas[new_log({new_task({new_mozharness({test,gecko,}),perfherder,}),})] = {"win_mda2_M-fis","osx_dt8_M-e10s","osx_3_M","osx_2_M","win_gl1c_M-e10s","osx_bc4_M","win_gpu_M","osx_dt3_M-fis","win_dt4_M","win_3_M","osx_4_M","osx_bc2_M-e10s","win_h2_M-e10s","osx_bc12_M","osx_mda4_M-fis","osx_bc5_M-fis","win_dt10_M","osx_gpu_M-fis","win_1_M-e10s","win_a11y_M-1proc","osx_bc3_M-e10s","win_gl2c_M","win_dt6_M-e10s","win_h1_M-e10s","osx_4_M-e10s","win_gl2e3_M","osx_c1_M-1proc","osx_dt3_M","osx_dt2_M","win_gl2e1_M","osx_bc8_M-e10s","win_bc4_M-e10s","osx_gpu_M","win_mda_M","osx_5_M-e10s","win_h4_M-e10s","win_dt3_M-e10s","win_gl1e_M-fis","win_mda1_M","win_dt5_M-e10s","win_dt1_M-e10s","osx_dt1_M-e10s","osx_bc5_M-e10s","osx_gl1c_M","osx_dt5_M","osx_mda4_M-spi","osx_bc2_M-fis","win_mda3_M","win_gpu_M-e10s","osx_bc7_M","osx_mda_M-e10s","osx_TV1_?","osx_bc7_M-e10s","osx_bc4_M-e10s","osx_bc1_M","win_TV1_?","osx_bc6_M","win_7_M","win_inst_M","win_gl2e4_M-fis","osx_TV2_?","win_mda2_M-e10s","osx_bc11_M-fis","win_mda_M-spi","osx_bc9_M","osx_1_M","win_a11y_M","osx_bc6_M-e10s","osx_dt13_M","osx_bc6_M-fis","win_dt2_M","osx_dt10_M","osx_4_M-fis","osx_mda3_M-fis","win_4_M","osx_dt3_M-e10s","win_gl2e2_M-e10s","win_c1_M-1proc","osx_bc10_M-e10s","win_gl2e3_M-fis","win_dt11_M","osx_dt7_M-fis","osx_dt9_M","win_gl2c_M-e10s","osx_dt7_M-e10s","win_mda3_M-e10s-spi","osx_bc11_M","win_2_M-e10s","osx_mda3_M-spi","win_mda1_M-e10s","win_bc3_M-e10s","win_gl1e_M-e10s","osx_mda3_M","osx_bc1_M-fis","osx_bc10_M-fis","win_c2_M-1proc","win_8_M","win_9_M","osx_TV3_?","win_10_M","win_gl2c_M-fis","osx_bct_M","osx_bc11_M-e10s","win_dt14_M","osx_2_M-e10s","win_bc2_M","win_c3_M-1proc","win_gl2e4_M","osx_dt5_M-fis","win_mda2_M","osx_mda2_M-fis","win_dt8_M-e10s","win_5_M","win_dt7_M-e10s","osx_gl1_M-e10s","osx_bc2_M","osx_dt5_M-e10s","osx_dt1_M","osx_gl1c_M-fis","osx_8_M","win_bc6_M","osx_cl_M-e10s","win_dt4_M-fis","osx_dt6_M","osx_dt7_M","win_6_M","win_bc7_M","osx_dt6_M-fis","win_bc1_M","osx_5_M-fis","osx_gl2c_M-fis","osx_bc3_M","osx_c3_M-1proc","win_bc3_M","win_dt7_M","osx_dt4_M","win_mda1_M-e10s-spi","win_dt4_M-e10s","win_dt6_M-fis","osx_9_M","osx_bc8_M-fis","osx_c2_M","win_c2_M","win_5_M-e10s","osx_bc12_M-e10s","osx_7_M","win_dt9_M","win_h3_M-e10s","osx_bc8_M","win_gl2e4_M-e10s","win_gl2e2_M-fis","win_bct_M","osx_bc9_M-e10s","win_c3_M","osx_1_M-e10s","win_mda_M-e10s","win_gl2e1_M-e10s","win_bc6_M-e10s","osx_dt1_M-fis","win_cl_M-e10s","osx_mda2_M-spi","win_dt6_M","win_bc5_M-e10s","win_gl1e_M","win_gl2e1_M-fis","win_mda3_M-e10s","win_bc1_M-e10s","win_mda3_M-fis","win_mda3_M-spi","win_mda1_M-spi","osx_c2_M-1proc","osx_mda1_M-fis","win_mda_M-e10s-spi","win_dt3_M","win_mda2_M-spi","osx_gl1e_M-e10s","osx_bc4_M-fis","win_3_M-e10s","win_c1_M","osx_bc12_M-fis","osx_bc7_M-fis","win_gl1c_M-fis","osx_gl1e_M-fis","osx_dt4_M-fis","osx_5_M","osx_dt2_M-fis","osx_bc9_M-fis","osx_bc10_M","osx_gl3_M-e10s","osx_mda2_M","win_bc5_M","win_bc7_M-e10s","osx_bc3_M-fis","osx_3_M-e10s","win_dt3_M-fis","osx_dt4_M-e10s","osx_gpu_M-e10s","win_mda2_M-e10s-spi","win_1_M","osx_dt8_M-fis","win_dt13_M","win_gl2e2_M","win_dt8_M","osx_6_M","osx_c1_M","win_dt1_M","osx_a11y_M","osx_mda1_M","win_bc2_M-e10s","osx_2_M-fis","win_TC1_?","win_TC3_?","osx_mda4_M","osx_bc5_M","win_TV2_?","win_dt5_M","osx_1_M-fis","osx_mda_M-e10s-spi","win_gl2e3_M-e10s","win_dt2_M-e10s","osx_gl1c_M-e10s","osx_gl2c_M-e10s","osx_dt2_M-e10s","osx_gl2_M-e10s","win_bc4_M","osx_ss_M-fis","win_gl1c_M","osx_gl1e_M","win_2_M","osx_mda1_M-spi","osx_dt8_M","win_ss_M","win_4_M-e10s","osx_bc1_M-e10s","osx_3_M-fis","osx_c3_M","win_dt12_M","osx_gl2c_M","osx_dt6_M-e10s","osx_a11y_M-1proc",}
schemas[new_log({new_task({new_mozharness({download,}),perfherder,}),task_exit,})] = {"osx_si_L10n-Rpk","osx_tl_L10n-Rpk","osx_fy-NL_L10n-Rpk","osx_xh_L10n-Rpk","osx_gu-IN_L10n-Rpk","osx_mr_L10n-Rpk","osx_et_L10n-Rpk","osx_br_L10n-Rpk","osx_da_L10n-Rpk","osx_es-CL_L10n-Rpk","osx_ur_L10n-Rpk","osx_tr_L10n-Rpk","osx_gn_L10n-Rpk","osx_rm_L10n-Rpk","osx_eo_L10n-Rpk","osx_my_L10n-Rpk","osx_Nr_?","osx_cy_L10n-Rpk","osx_ast_L10n-Rpk","osx_hi-IN_L10n-Rpk","osx_kn_L10n-Rpk","osx_kk_L10n-Rpk","osx_hr_L10n-Rpk","osx_fr_L10n-Rpk","osx_sk_L10n-Rpk","osx_sq_L10n-Rpk","osx_son_L10n-Rpk","osx_wo_L10n-Rpk","osx_uk_L10n-Rpk","osx_oc_L10n-Rpk","osx_ar_L10n-Rpk","osx_is_L10n-Rpk","osx_gl_L10n-Rpk","osx_km_L10n-Rpk","osx_an_L10n-Rpk","osx_eu_L10n-Rpk","osx_vi_L10n-Rpk","osx_pa-IN_L10n-Rpk","osx_lo_L10n-Rpk","osx_ia_L10n-Rpk","osx_es-AR_L10n-Rpk","osx_mk_L10n-Rpk","osx_ta_L10n-Rpk","osx_he_L10n-Rpk","osx_lt_L10n-Rpk","osx_gd_L10n-Rpk","osx_ach_L10n-Rpk","osx_nn-NO_L10n-Rpk","android_run_Bpgo","osx_ms_L10n-Rpk","osx_pt-PT_L10n-Rpk","osx_en-GB_L10n-Rpk","osx_dsb_L10n-Rpk","osx_id_L10n-Rpk","osx_es-ES_L10n-Rpk","osx_hsb_L10n-Rpk","osx_lv_L10n-Rpk","osx_ff_L10n-Rpk","osx_ne-NP_L10n-Rpk","osx_cs_L10n-Rpk","osx_hu_L10n-Rpk","osx_uz_L10n-Rpk","osx_sl_L10n-Rpk","osx_es-MX_L10n-Rpk","osx_nb-NO_L10n-Rpk","osx_ka_L10n-Rpk","osx_ca_L10n-Rpk","osx_Rpk_?","osx_sv-SE_L10n-Rpk","osx_trs_L10n-Rpk","osx_ru_L10n-Rpk","osx_nl_L10n-Rpk","osx_ltg_L10n-Rpk","android_B_?","osx_te_L10n-Rpk","osx_az_L10n-Rpk","osx_be_L10n-Rpk","osx_th_L10n-Rpk","osx_crh_L10n-Rpk","osx_de_L10n-Rpk","osx_kab_L10n-Rpk","osx_zh-TW_L10n-Rpk","osx_bs_L10n-Rpk","osx_sr_L10n-Rpk","osx_fi_L10n-Rpk","linux_Sa_?","osx_ga-IE_L10n-Rpk","osx_bn_L10n-Rpk","osx_lij_L10n-Rpk","osx_cak_L10n-Rpk","osx_en-CA_L10n-Rpk","osx_fa_L10n-Rpk","osx_hy-AM_L10n-Rpk","osx_ja-JP-mac_L10n-Rpk","osx_it_L10n-Rpk","osx_pl_L10n-Rpk","osx_el_L10n-Rpk","osx_ro_L10n-Rpk","osx_ko_L10n-Rpk","osx_zh-CN_L10n-Rpk","osx_pt-BR_L10n-Rpk","osx_bg_L10n-Rpk","osx_af_L10n-Rpk",}
schemas[new_log({new_task({new_mozharness({perfherder,}),}),})] = {"linux_tp6-c-3_Rap","osx_sb_Rap-Cr","win_mm-a_Rap","linux_wa_Rap","android_tp6m-c-3_Rap-fenix","osx_tp6-10_Rap","osx_sy-d_SY","android_tp6m-9_Rap","android_tp6m-c-12-f64_Rap-1proc","win_wa_Rap","linux_tp6-5_Rap","android_sp_Rap-P","linux_wm-i_Rap","android_tp6m-c-5-f64_Rap-1proc","osx_tp6-4_Rap-Cr","linux_tp6-c-4_Rap","win_ss_Rap-Cr","osx_tp6-6_Rap-Cr","android_tp6m-c-10_Rap","android_tp6m-6_Rap","win_tp6-c-1_Rap-Cr","android_tp6m-c-12_Rap-fenix","android_tp6m-4_Rap","win_tp6-3_Rap-Cr","linux_godot_Rap","osx_tp6-10_Rap-Cr","android_tp6m-c-11_Rap","win_sp_Rap-Cr","android_ytp_Rap","linux_tp6-2_Rap-Cr","android_tp6m-c-2_Rap-fenix","linux_tp6-9_Rap","linux_tp6-c-3_Rap-Cr","android_ugl_Rap","win_tp6-7_Rap","linux_tp6-1_Rap-Cr","osx_tp6-8_Rap","android_tp6m-c-3_Rap","linux_tp6-3_Rap","win_tp6-b-1_Rap","android_tp6m-c-4_Rap-fenix","win_tp6-5_Rap-Cr","android_tp6m-c-11_Rap-fenix","win_sp_Rap","android_tp6m-7_Rap","android_tp6m-c-5_Rap","osx_ytp_Rap","osx_wa_Rap-Cr","osx_ss_Rap-Cr","win_tp6-3_Rap","android_tp6m-c-10-f64_Rap-1proc","linux_tp6-c-1_Rap","android_tp6m-c-13-f64_Rap-1proc","android_tp6m-c-1-f64_Rap-1proc","osx_tp6-9_Rap","osx_tp6-c-3_Rap-Cr","linux_wm-c_Rap","linux_ss_Rap","android_tp6m-c-13_Rap","osx_mm-h_Rap-Cr","win_tp6-c-2_Rap","android_tp6m-c-1_Rap-fenix","osx_godot_Rap","linux_ss_Rap-Cr","linux_tp6-b-1_Rap","osx_mm-a_Rap","linux_ytp_Rap","android_tp6m-3_Rap","linux_mm-a_Rap","win_tp6-2_Rap-Cr","win_tp6-6_Rap","osx_tp6-3_Rap","android_tp6m-c-2-f64_Rap-1proc","win_tp6-8_Rap","linux_tp6-2_Rap","linux_sb_Rap-Cr","win_tp6-4_Rap-Cr","android_tp6m-10_Rap","osx_tp6-1_Rap-Cr","android_tp6m-c-8_Rap-fenix","win_tp6-c-3_Rap-Cr","android_tp6m-c-6_Rap-fenix","linux_tp6-6_Rap","android_tp6m-c-7_Rap","android_tp6m-c-14_Rap","win_tp6-c-2_Rap-Cr","osx_tp6-4_Rap","osx_tp6-7_Rap","win_godot_Rap-Cr","osx_tp6-c-1_Rap","osx_tp6-c-2_Rap","osx_wa_Rap","android_tp6m-c-1_Rap","osx_tp6-9_Rap-Cr","win_ss_Rap","win_tp6-1_Rap-Cr","android_tp6m-c-3-f64_Rap-1proc","win_tp6-c-3_Rap","android_tp6m-c-7-f64_Rap-1proc","android_tp6m-c-9_Rap-fenix","osx_tp6-c-4_Rap","android_tp6m-c-4-f64_Rap-1proc","android_tp6m-c-13_Rap-fenix","android_tp6m-c-9_Rap","android_sp_Rap","android_tp6m-c-8-f64_Rap-1proc","linux_tp6-3_Rap-Cr","osx_tp6-8_Rap-Cr","osx_mm-a_Rap-Cr","linux_tp6-c-1_Rap-Cr","win_godot_Rap","win_tp6-c-1_Rap","android_tp6m-c-6-f64_Rap-1proc","linux_dom_Rap-Cr","win_sb_Rap","android_tp6m-c-11-f64_Rap-1proc","osx_tp6-7_Rap-Cr","android_tp6m-c-7_Rap-fenix","android_tp6m-c-10_Rap-fenix","win_tp6-2_Rap","linux_sp_Rap-Cr","linux_tp6-c-4_Rap-Cr","linux_godot-b_Rap","linux_ugl_Rap-Cr","linux_ugl_Rap","android_tp6m-8_Rap","linux_wm-b_Rap","android_tp6m-c-12_Rap","osx_tp6-6_Rap","linux_godot-c_Rap","osx_tp6-5_Rap","android_tp6m-2_Rap","win_tp6-9_Rap-Cr","osx_tp6-3_Rap-Cr","android_tp6m-c-8_Rap","osx_tp6-2_Rap","linux_mm-a_Rap-Cr","linux_tp6-4_Rap","linux_tp6-4_Rap-Cr","osx_tp6-5_Rap-Cr","win_tp6-5_Rap","win_wa_Rap-Cr","osx_tp6-b-1_Rap","android_ytp_Rap-fenix","osx_tp6-1_Rap","win_tp6-10_Rap","android_sp_Rap-1proc","osx_mm-h_Rap","linux_wa_Rap-Cr","win_tp6-8_Rap-Cr","android_tp6m-5_Rap","linux_tp6-6_Rap-Cr","win_mm-a_Rap-Cr","linux_sp_Rap","linux_tp6-7_Rap-Cr","linux_mm-h_Rap","win_tp6-1_Rap","win_ytp_Rap","linux_wm_Rap","linux_tp6-c-2_Rap-Cr","osx_sb_Rap","win_sb_Rap-Cr","linux_tp6-10_Rap-Cr","osx_tp6-c-1_Rap-Cr","win_mm-h_Rap","win_tp6-6_Rap-Cr","osx_tp6-c-3_Rap","osx_sp_Rap-Cr","android_tp6m-c-4_Rap","win_tp6-10_Rap-Cr","linux_tp6-10_Rap","osx_tp6-2_Rap-Cr","win_tp6-4_Rap","linux_mm-h_Rap-Cr","linux_sb_Rap","android_tp6m-c-4_Rap-1proc","win_tp6-9_Rap","linux_tp6-8_Rap","win_mm-h_Rap-Cr","linux_tp6-9_Rap-Cr","win_tp6-c-4_Rap","win_tp6-c-4_Rap-Cr","android_tp6m-c-14-f64_Rap-1proc","linux_tp6-8_Rap-Cr","linux_wm_Rap-Cr","linux_tp6-7_Rap","linux_godot-i_Rap","linux_dom_Rap","android_tp6m-c-2_Rap","win_tp6-7_Rap-Cr","linux_godot_Rap-Cr","linux_tp6-5_Rap-Cr","osx_sp_Rap","osx_godot_Rap-Cr","linux_tp6-c-2_Rap","osx_tp6-c-2_Rap-Cr","android_idl_Rap-P","linux_tp6-1_Rap","android_tp6m-1_Rap","osx_tp6-c-4_Rap-Cr","android_tp6m-c-6_Rap","osx_ss_Rap",}
schemas[new_log({new_task({new_mozharness({test,perfherder,}),}),})] = {"win_g1_T","osx_ps_T","win_tp_T","osx_sy_SY","win_smw_T","linux_d_T","win_d_T","linux_smw_T","linux_o_T","linux_c_T","win_bcv_T","win_ps_T","osx_damp_T","osx_g5_T","linux_ps_T","osx_c_T","osx_g4_T","linux_bcv_T","linux_ps_T-e10s","win_g5_T","osx_ab-d_SY","linux_tp_T","linux_damp_T","osx_g1_T","linux_tp6_Tss","osx_o_T","osx_p_T","linux_s_T","win_ab_SY","win_sy-tp6_SY","win_s_T","win_c_T","win_x_T","osx_smw_T","osx_tp_T","win_sy-d_SY","osx_ab_SY-e10s","win_sy_SY-e10s","osx_s_T","osx_bcv_T","linux_p_T","osx_ab_SY","osx_d_T","win_o_T","win_p_T","linux_g1_T","linux_g5_T","linux_g3_T","linux_tabswitch_T","osx_tp6_Tss","win_ab-d_SY","win_damp_T","win_ab_SY-e10s","linux_f_T","linux_g4_T","osx_sy-tp6_SY","osx_sy_SY-e10s","win_tabswitch_T","win_sy_SY","win_g4_T",}
schemas[new_log({new_task({new_mozharness({upload,download,perfherder,}),perfherder,}),task_exit,})] = {"android_instr_Bpgo","linux_instr_Bpgo","linux_idx_Searchfox","osx_idx_Searchfox",}
schemas[new_log({new_task({download,perfherder,}),})] = {"other_rust-size_TW64","win_cgc_SM","win_p_SM","other_sccache_TW64","win_wrench_WR","other_cbindgen_TW64",}
schemas[new_log({new_task({new_mozharness({package_tests,upload,download,perfherder,}),perfherder,}),task_exit,})] = {"linux_V_?","linux_Bg_?","android_B_Bpgo","android_Bg_?","android_N_?","linux_B_Bpgo","linux_B_?","linux_Bb_?","linux_N_?","osx_Bf_?","osx_N_?","osx_Bg_?","linux_Bf_?","android_Bf_?","linux_Bbc_?","android_idx_Searchfox",}
schemas[new_log({new_task({new_mozharness({upload,download,perfherder,}),perfherder,}),})] = {"win_idx_Searchfox",}
schemas[new_log({new_task({new_mozharness({upload,download,package_tests,}),perfherder,}),task_exit,})] = {"osx_Ba_?","android_Ba_?","linux_AB_?","linux_Ba_?",}
schemas[new_log({new_task({new_mozharness({}),}),task_exit,})] = {"android_46_M","android_54_M","android_59_M","android_2_M-e10s","android_13_M","android_c2_M-1proc","android_20_M","android_c6_M","android_9_M-1proc","android_wpt1_W-fis","android_43_M","android_58_M-1proc","android_c1_M-1proc","android_53_M","android_5_M","android_37_M-1proc","android_41_M-1proc","android_10_M","android_30_M","android_23_M-1proc","android_22_M","android_50_M","android_25_M","android_16_M","linux_TVw-sw_?","android_2_M-1proc","android_42_M-1proc","android_4_M-e10s","android_TV1_?","android_53_M-1proc","android_18_M-1proc","android_57_M","android_58_M","android_52_M-1proc","android_49_M-1proc","android_10_M-1proc","android_c6_M-1proc","android_32_M-1proc","android_gpu_M","android_8_M-1proc","android_57_M-1proc","android_39_M","android_8_M","android_55_M","android_21_M","android_3_M-1proc","android_33_M-1proc","android_52_M","android_3_M","android_c1_M","android_24_M-1proc","android_14_M","android_c2_M","android_28_M-1proc","android_mda1_M","android_35_M","android_7_M","android_12_M","android_19_M-1proc","android_22_M-1proc","android_35_M-1proc","android_38_M","android_49_M","android_40_M-1proc","android_44_M","android_43_M-1proc","android_17_M","android_51_M","android_cl_M","android_46_M-1proc","android_33_M","android_c8_M","android_mda1_M-1proc","android_cl_M-e10s","android_34_M","android_c3_M","android_c4_M-1proc","android_45_M","android_11_M","android_mda3_M","android_c7_M","linux_TVw_?","android_29_M-1proc","android_c3_M-1proc","android_1_M","android_11_M-1proc","android_1_M-1proc","android_30_M-1proc","android_3_M-e10s","android_6_M","android_23_M","android_48_M","android_28_M","android_4_M-1proc","android_7_M-1proc","android_26_M","android_50_M-1proc","android_56_M-1proc","android_59_M-1proc","android_36_M-1proc","android_20_M-1proc","android_27_M-1proc","android_27_M","android_31_M-1proc","android_18_M","android_1_M-e10s","android_TV2_?","android_55_M-1proc","android_9_M","android_54_M-1proc","android_gpu_M-1proc","android_56_M","android_34_M-1proc","android_26_M-1proc","android_c5_M-1proc","android_51_M-1proc","android_21_M-1proc","android_13_M-1proc","android_14_M-1proc","android_41_M","android_TV_?","android_6_M-1proc","android_37_M","android_45_M-1proc","android_38_M-1proc","android_47_M-1proc","android_17_M-1proc","android_15_M","android_19_M","android_c4_M","android_24_M","android_44_M-1proc","android_60_M-1proc","android_40_M","android_36_M","android_c7_M-1proc","android_15_M-1proc","android_mda2_M","android_29_M","android_39_M-1proc","android_25_M-1proc","android_32_M","android_5_M-1proc","android_48_M-1proc","android_31_M","android_12_M-1proc","android_47_M","android_16_M-1proc","android_2_M","android_c5_M","android_4_M","android_60_M","android_42_M","android_c8_M-1proc","android_gpu_M-e10s",}
schemas[new_log({new_task({new_mozharness({gecko,}),perfherder,}),})] = {"win_gl5_M-e10s","win_gl2_M-e10s","win_gl3_M-e10s","win_gl7_M-e10s","win_gl1_M-e10s","win_gl4_M-e10s","win_gl6_M-e10s","win_gl8_M-e10s","win_h5_M-e10s",}
schemas[new_log({new_task({new_mozharness({test,gecko,test_ref,}),perfherder,}),task_exit,})] = {"linux_TV3_?","linux_TC2_?",}
schemas[new_log({new_task({new_mozharness({perfherder,download,}),perfherder,}),})] = {"win_S_?",}
schemas[new_log({new_task({new_mozharness({upload,download,package_tests,}),perfherder,}),})] = {"win_Ba_?","win_N_?","win_Be_?",}
schemas[new_log({new_task({}),task_exit,})] = {"osx_sv-SE_p","linux_ach_p","osx_az_p","win_bs_p","other_SDR_?","linux_eu_p","osx_N_p","win_ltg_p","osx_lij_p","win_sl_p","linux_an_p","linux_mulmod_MPI","other_wine-3.0.3_Fetch-URL","other_bmul_SAW","osx_fy-NL_p","other_valgrind_Deb7","osx_sk_p","osx_hu_p","linux_bn_p","osx_id_p","linux_DocUpload_?","linux_CRMF_?","osx_pt-BR_p","osx_lo_p","linux_en-GB_p","osx_si_p","osx_eo_p","linux_be_p","linux_Chains_?","osx_ltg_p","other_devscripts_Deb7","osx_oc_p","win_lt_p","osx_son_p","osx_my_p","linux_modular_Builds","other_sqlite3_Deb7","osx_ff_p","android_gpc-n_pub","osx_pt-PT_p","osx_ko_p","osx_pa-IN_p","osx_sr_p","android_nightly-A_?","linux_uk_p","linux_Certs-F_FIPS","win_uz_p","android_3_M-fis","win_nb-NO_p","linux_B_Test","osx_bg_p","linux_gcc-6_Builds","osx_tr_p","win_bn_p","linux_pt-PT_p","linux_SDR_?","win_pt-PT_p","other_cmake_Deb7","linux_kk_p","osx_ar_p","linux_km_p","linux_add_MPI","other_scan-build_?","linux_gd_p","linux_hy-AM_p","win_sv-SE_p","other_xkbc_Deb7","linux_Gtest_?","osx_hr_p","linux_invmod_MPI","osx_lv_p","linux_af_p","osx_he_p","win_si_p","android_gps-n_pub","linux_zh-CN_p","linux_gu-IN_p","osx_kab_p","linux_DB_?","win_en-GB_p","linux_Tools_?","other_hg_Deb9","other_zlib-1.2.11_Fetch-URL","osx_wo_p","win_tr_p","linux_ga-IE_p","osx_hsb_p","other_Default_Cipher","linux_gcc-5_Builds","linux_zh-TW_p","osx_pl_p","other_Lowhash_?","win_is_p","linux_te_p","linux_si_p","osx_fa_p","other_nsis-3.01_Fetch-URL","other_hacl_?","win_th_p","linux_id_p","osx_zh-TW_p","linux_es-ES_p","linux_lij_p","linux_ia_p","osx_br_p","other_gmp-5.1.3_Fetch-URL","linux_ko_p","other_dependencies_?","other_xkbdconfig_Deb7-32","linux_mr_p","win_ko_p","win_km_p","linux_ar_p","linux_server_TLS","linux_B_FIPS","other_Coverage_?","linux_mod_MPI","osx_ro_p","win_be_p","linux_Gtest_Test","android_2_M-fis","osx_es-CL_p","osx_el_p","win_af_p","android_4_M-fis","linux_B_TLS","osx_ia_p","osx_is_p","win_nn-NO_p","other_gdkpixbuf_Deb7","win_sr_p","android_T_debug","android_Dev build_?","other_xz_Deb7","linux_nl_p","other_pcre3_Deb7","osx_mr_p","linux_mk_p","other_ChaCha20_SAW","osx_cy_p","win_es-ES_p","osx_km_p","win_crh_p","osx_ur_p","osx_gu-IN_p","win_es-AR_p","linux_vi_p","other_lint_?","linux_lo_p","osx_et_p","other_apt_Deb7","other_python-defaults_Deb7","win_ru_p","osx_kn_p","linux_ja_p","win_vi_p","linux_oc_p","win_fy-NL_p","osx_cs_p","osx_crh_p","osx_de_p","win_hy-AM_p","osx_th_p","win_pt-BR_p","linux_Tidy_?","osx_sq_p","linux_QuickDER_?","other_nasm-2.14.02_Fetch-URL","linux_sl_p","win_bg_p","osx_ta_p","win_ne-NP_p","android_A_raptor","other_gtk3_Deb7-32","linux_sub_MPI","win_lv_p","other_harfbuzz_Deb7-32","osx_trs_p","win_cs_p","other_raptor-D_?","linux_ms_p","linux_submod_MPI","win_he_p","linux_pt-BR_p","linux_br_p","win_an_p","win_mk_p","osx_dsb_p","android_Nightly build and upload_?","other_ninja_Deb7","win_gu-IN_p","osx_nl_p","linux_eo_p","win_zh-TW_p","osx_es-ES_p","other_python3-defaults_Deb7","android_A_forPerformanceTest","win_az_p","linux_es-MX_p","linux_NoPCLMUL_Cipher","linux_dtls-server_TLS","other_pcre3_Deb7-32","osx_xh_p","osx_rm_p","other_nightly-D_?","other_Poly1305_SAW","other_gdb_Deb7","other_abi_?","linux_xh_p","linux_NoAESNI_Cipher","other_atk_Deb7","osx_be_p","linux_pkix_SSL","win_es-MX_p","win_uk_p","linux_nb-NO_p","osx_en-CA_p","android_gpu_M-fis","linux_ru_p","other_Certs-F_FIPS","other_glib_Deb7","osx_eu_p","osx_fr_p","linux_Tests-F_FIPS","linux_sq_p","osx_es-AR_p","win_ms_p","win_nl_p","other_xkbc_Deb7-32","linux_hu_p","other_dh-python_Deb7","linux_fr_p","osx_en-GB_p","other_dpkg_Deb7","linux_fi_p","linux_fa_p","other_git_Deb7","win_ach_p","linux_rm_p","win_cy_p","linux_ast_p","win_kab_p","win_ca_p","other_mpc-0.8.2_Fetch-URL","other_wayland_Deb7","other_gtk3_Deb7","other_hg_Deb7","linux_div_MPI","linux_Nightly_?","linux_CertDN_?","linux_expmod_MPI","win_my_p","linux_lv_p","linux_is_p","win_lij_p","linux_es-AR_p","linux_en-CA_p","osx_sl_p","win_hr_p","other_python3.5_Deb7","other_python-zstandard_Deb9","osx_hy-AM_p","linux_RustNightly_?","win_ta_p","android_1_M-fis","linux_ca_p","win_pl_p","linux_NoSSSE3|NEON_Cipher","linux_dsb_p","linux_Certs_?","linux_tlsfuzzer_?","linux_EC_?","win_pa-IN_p","other_wix-3.1.1_Fetch-URL","linux_cs_p","other_DB_?","osx_af_p","osx_te_p","win_fr_p","other_pango_Deb7","linux_Bogo_?","win_es-CL_p","linux_Merge_?","linux_it_p","osx_da_p","linux_he_p","osx_ja-JP-mac_p","linux_sqr_MPI","osx_fi_p","osx_gl_p","osx_mk_p","linux_client_TLS","linux_kab_p","linux_sk_p","other_isl-0.15_Fetch-URL","other_mpfr-3.1.5_Fetch-URL","linux_pa-IN_p","win_ff_p","osx_lt_p","win_hsb_p","linux_Default_Cipher","win_kn_p","win_rm_p","linux_server-nfm_TLS","other_am_Deb7","osx_nb-NO_p","linux_ur_p","win_en-CA_p","win_da_p","other_pango_Deb7-32","win_dsb_p","linux_el_p","win_br_p","osx_ka_p","linux_da_p","win_hu_p","android_Release_?","other_glib_Deb7-32","linux_de_p","other_gcc-6.4.0_Fetch-URL","other_make_Deb7","linux_dtls-server-nfm_TLS","win_eo_p","win_ia_p","linux_trs_p","linux_gcc-4.8_Builds","linux_addmod_MPI","other_harfbuzz_Deb7","win_gn_p","linux_ltg_p","win_et_p","linux_th_p","linux_ta_p","win_id_p","linux_cy_p","linux_SMIME_?","osx_ru_p","osx_ast_p","osx_ga-IE_p","win_gl_p","android_compare-locale_?","win_fi_p","win_it_p","linux_son_p","linux_r_Snap","win_kk_p","win_oc_p","linux_Lowhash_?","win_el_p","win_de_p","linux_mpi_Test","linux_fy-NL_p","linux_client-nfm_TLS","win_ka_p","osx_zh-CN_p","other_B_SAW","linux_lt_p","osx_ne-NP_p","linux_es-CL_p","other_nasm-2.13.02_Fetch-URL","other_python_Deb7","win_sk_p","osx_an_p","win_N_p","win_sq_p","osx_bs_p","win_xh_p","win_ja_p","linux_sharedb_SSL","win_trs_p","win_hi-IN_p","win_ro_p","win_lo_p","osx_vi_p","linux_Policy_?","osx_uz_p","linux_ka_p","other_clang-format_?","other_ktlint_?","other_binutils-2.27_Fetch-URL","linux_ne-NP_p","linux_bs_p","linux_ff_p","osx_it_p","win_ga-IE_p","linux_gcc-4.4_Builds","win_son_p","linux_et_p","win_mr_p","android_A_debug","linux_Tidy+Unit+Doc_?","linux_MPI_?","other_Chains_?","linux_pl_p","osx_gn_p","other_python-zstandard_Deb7","win_gd_p","linux_my_p","other_SMIME_?","linux_hi-IN_p","linux_sr_p","linux_wo_p","linux_dtls-client-nfm_TLS","linux_ro_p","win_ar_p","other_B_FIPS","win_zh-CN_p","osx_nn-NO_p","linux_N_p","other_pkix_SSL","linux_hr_p","linux_hsb_p","osx_ms_p","other_CRMF_?","linux_sqrmod_MPI","osx_cak_p","linux_crh_p","linux_sv-SE_p","osx_uk_p","other_Tools_?","osx_ca_p","linux_gn_p","win_tl_p","linux_upgradedb_SSL","win_ast_p","osx_kk_p","linux_bg_p","other_binutils-2.31.1_Fetch-URL","linux_Interop_?","other_compare-locale_?","linux_dtls-client_TLS","osx_es-MX_p","linux_nn-NO_p","linux_kn_p","android_C_R-fis","win_fa_p","other_Policy_?","linux_clang-4_Builds","android_NA_?","other_D-PR_?","osx_bn_p","linux_Decision_?","win_eu_p","win_te_p","linux_gl_p","linux_tl_p","osx_gd_p","other_gdkpixbuf_Deb7-32","linux_NoAVX_Cipher","linux_az_p","linux_uz_p","win_cak_p","osx_hi-IN_p","osx_ach_p","win_ur_p","linux_cak_p","other_wayland_Deb7-32","osx_tl_p","linux_tr_p","other_detekt_?","other_atk_Deb7-32","linux_standard_SSL","win_wo_p",}
schemas[new_log({new_task({new_mozharness({test_ref,}),}),})] = {"android_J12_R-1proc","android_J7_R-1proc","android_J9_R-1proc","android_J8_R-1proc","android_J3_R-1proc","android_J6_R-1proc","android_J2_R-1proc","android_J5_R-1proc","android_J11_R-1proc","android_J1_R-1proc","android_J10_R-1proc","android_J4_R-1proc",}
schemas[new_log({new_task({new_mozharness({test,gecko,}),}),})] = {"win_5_M-fis","win_4_M-fis","win_inst_M-fis","win_bc2_M-fis","win_bc3_M-fis","osx_dt-wr_M-fis","win_dt5_M-fis","osx_dt12_M","osx_dt-wr_M","win_bc4_M-fis","osx_ss_M","win_bc5_M-fis","win_3_M-fis","win_bc7_M-fis","win_bc1_M-fis","win_dt16_M","win_bc6_M-fis",}
schemas[new_log({new_task({new_mozharness({test,}),perfherder,}),task_exit,})] = {"linux_X1_X-sw","linux_X6_X-sw","linux_X5_X","linux_X4_X-sw","linux_X6_X","linux_X3_X-fis","linux_X5_X-sw","linux_X10_X","linux_X11_X","linux_X4_X","linux_X5_X-fis","linux_X1_X-fis","linux_X1_X","linux_X3_X","linux_X8_X","linux_Cpp_?","linux_X2_X","linux_X2_X-sw","linux_X6_X-fis","linux_X9_X","linux_X2_X-fis","linux_X7_X","linux_X12_X","linux_X4_X-fis","linux_X3_X-sw",}
schemas[new_log({new_task({new_mozharness({}),perfherder,}),})] = {"win_Z2_Z","osx_Jit1_?","win_TC_?","win_TVg_?","win_TV_?","win_Jit5_?","osx_Z1_Z","osx_Z2_Z","win_Jit3_?","osx_Z4_Z","win_Z1_Z","win_Jit_?","osx_Jit2_?","osx_TV_?","osx_TVg_?","win_Jit1_?","osx_Jit3_?","osx_Z3_Z","win_Jit6_?","win_Z3_Z","osx_Jit_?","win_Jit2_?","win_Z4_Z",}
schemas[new_log({new_task({new_mozharness({test_gtest,perfherder,}),perfherder,}),task_exit,})] = {"linux_GTest_?",}
schemas[new_log({new_task({new_mozharness({perfherder,upload,download,package_tests,}),perfherder,}),})] = {"win_BoR_?","win_Bof_?","win_Bd_?","win_Bo_?",}
schemas[new_log({new_task({new_mozharness({}),}),})] = {"win_tp6-5_Rap-Prof","linux_godot_Rap-Prof","android_Jit2_?","osx_tp6-9_Rap-Prof","osx_tp6-5_Rap-Prof","osx_tp6-10_Rap-Prof","linux_wm_Rap-Prof","win_mm-h_Rap-Prof","android_Jit7_?","win_wa_Rap-Prof","win_mm-a_Rap-Prof","win_tp6-6_Rap-Prof","android_Jit9_?","osx_tp6-3_Rap-Prof","linux_tp6-3_Rap-Prof","linux_tp6-8_Rap-Prof","linux_ss_Rap-Prof","linux_wm-i_Rap-Prof","android_tp6m-4_Rap-fenix","linux_wa_Rap-Prof","osx_mm-h_Rap-Prof","linux_tp6-2_Rap-Prof","win_tp6-2_Rap-Prof","android_tp6m-c-10_Rap-1proc","osx_TVw_?","osx_tp6-8_Rap-Prof","android_Jit3_?","win_sp_Rap-Prof","osx_sb_Rap-Prof","win_sb_Rap-Prof","win_tp6-9_Rap-Prof","win_godot_Rap-Prof","win_tp6-3_Rap-Prof","osx_tp6-6_Rap-Prof","linux_godot-b_Rap-Prof","android_tp6m-c-1_Rap-1proc","android_tp6m-3_Rap-fenix","android_mda3_M-1proc","osx_godot_Rap-Prof","android_Jit4_?","win_TVw_?","win_tp6-10_Rap-Prof","linux_tp6-7_Rap-Prof","android_Jit6_?","osx_tp6-2_Rap-Prof","linux_wm-b_Rap-Prof","android_Jit8_?","win_ss_Rap-Prof","android_Jit1_?","android_tp6m-7-f64_Rap-1proc","linux_godot-c_Rap-Prof","android_tp6m-c-14_Rap-fenix","android_Jit5_?","android_mda2_M-1proc","linux_tp6-10_Rap-Prof","osx_mm-a_Rap-Prof","android_Jit10_?","osx_ss_Rap-Prof","linux_sp_Rap-Prof","android_tp6m-c-9-f64_Rap-1proc","osx_tp6-4_Rap-Prof","linux_tp6-6_Rap-Prof","linux_sb_Rap-Prof","linux_tp6-1_Rap-Prof","osx_tp6-1_Rap-Prof","linux_mm-a_Rap-Prof","linux_godot-i_Rap-Prof","osx_wa_Rap-Prof","android_tp6m-1-f64_Rap-1proc","linux_ugl_Rap-Prof","win_tp6-4_Rap-Prof","win_tp6-8_Rap-Prof","linux_dom_Rap-Prof","osx_sp_Rap-Prof","osx_tp6-7_Rap-Prof","linux_tp6-9_Rap-Prof","linux_tp6-5_Rap-Prof","linux_mm-h_Rap-Prof","win_tp6-7_Rap-Prof","linux_tp6-4_Rap-Prof","win_tp6-1_Rap-Prof","android_tp6m-c-8_Rap-1proc",}

for schema, tasks in pairs(schemas) do
    for i, task in ipairs(tasks) do
        schemas_map[task] = schema
    end
end


return M

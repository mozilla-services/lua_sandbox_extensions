-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Ingestion Monitor

Monitors the specified data ingestion errors and inactivity, partitioned by the
hierarchy configuration.

* ingestion_error   - monitors the ingestion error rate
* inactivity        - monitors for inactivity (no data)
* duplicates        - monitors the number of duplicates removed by ingestion
* capture_samples   - capture data samples for debugging

## Sample Configuration
```lua
filename        = "moz_ingest_doctype_monitor.lua"
docType         = "%s"
message_matcher = "Fields[docType] == '" .. docType .. "' && Logger == '%s'"
ticker_interval = 60
preserve_data   = true
output_limit    = 1024 * 1024 * 8
memory_limit    = 1024 * 1024 * 64
telemetry       = false --  when true appBuildId filtering discards anything older than 90 days
hierarchy       = {
    "Fields[normalizedChannel]",
}

alert = {
  disabled = false,
  prefix = true,
  throttle = 1440,
  modules = {
    email = {recipients = {"trink@mozilla.com"}},
  },

  thresholds = { -- map of hierarchy specified above
    ["*"] = {
      ingestion_error = 1.0, -- percent error (0.0 - 100.0, nil disables)
      duplicates      = 1.0, -- percent error (0.0 - 100.0, nil disables)
      inactivity      = 0, -- inactivity timeout in minutes (0 - 60, 0 == auto scale, nil disables)
      capture_samples = 2, -- number of samples to capture (1-10, nil disables)
    }
  }
}
preservation_version = 0 -- if the hierarchy is changed this must be incremented
```
--]]
_PRESERVATION_VERSION = read_config("preservation_version") or 0
data = {}

require "math"
require "string"
require "table"
require "hyperloglog"

local sats          = require "streaming_algorithms.time_series"
local p2            = require "streaming_algorithms.p2"
local alert         = require "heka.alert"
local escape_json   = require "lpeg.escape_sequences".escape_json

local SEC_IN_MINUTE     = 60
local TS_ROWS           = 61
local thresholds        = alert.thresholds
local title

local hierarchy = read_config("hierarchy") or {}
local function build_hierarchy()
    local path = {}
    for i,v in ipairs(hierarchy) do
        local typ = type(v)
        if typ == "string" then
            hierarchy[i] = function() return read_message(v) end
            path[#path + 1] = v
        elseif typ == "table" then
            local m = require(v.module)
            hierarchy[i] = function() return m[v.func](read_message(v.field)) end
            path[#path + 1] = v.field
        else
            error("invalid hierarchy type: ".. typ)
        end
    end
    title = string.format("%s\tSubmissions\tSubmissions Active Minutes\tSubmissions Current Data Gap\tSubmissions Quantile Data Gap" ..
                          "\tErrors\tErrors Active Minutes\tDuplicates\tDuplicates Active Minutes", table.concat(path, "\t"))
end
build_hierarchy()

local hierarchy_size = #hierarchy
local function validate_thresholds(t, path)
    if #path == hierarchy_size then
        for k, arg in pairs(t) do
            if k == "inactivity" then
                assert(type(arg) == "number" and arg >= 0 and arg <= 60,
                       string.format("%s: %s alert must contain a numeric timeout (0-60 minutes)", table.concat(path, "->"), k))
            elseif k == "ingestion_error" then
                assert(type(arg) == "number" and arg >= 0 and arg <= 100,
                       string.format("%s: %s alert must contain a numeric percent (0-100)", table.concat(path, "->"), k))
            elseif k == "duplicates" then
                assert(type(arg) == "number" and arg >= 0 and arg <= 100,
                       string.format("%s: %s alert must contain a numeric percent (0-100)", table.concat(path, "->"), k))
            elseif k == "capture_samples" then
                assert(type(arg) == "number" and arg > 0 and arg <= 10,
                       string.format("%s: %s alert must contain a numeric value (1-10)", table.concat(path, "->"), k))
            else
                error(string.format("%s: %s invalid alert type", table.concat(path, "->"), k))
            end
        end
    else
        for k, v in pairs(t) do
            path[#path + 1] = k
            validate_thresholds(v, path) -- if the full hierarchy is not specified, everything below is disabled
            if k == "*" then
                setmetatable(t, {__index = function() return v end})
            end
            table.remove(path)
        end
    end
    return true
end
validate_thresholds(thresholds, {})


local function get_tcfg(path)
    local tcfg = thresholds
    for i=1, hierarchy_size do
        if tcfg then tcfg = tcfg[path[i]] end
    end
    return tcfg or {}
end


local function new_capture_table()
    return {
               success = {
                   idx     = 1,
                   items   = {},
                   flag    = true,
               },
               errors = {
                   idx     = 1,
                   items   = {},
                   flag    = true,
                   }
           }
end


local function reload_tcfg(d, path)
    if #path == hierarchy_size then
        local ntcfg = get_tcfg(path)
        if d.tcfg and d.tcfg.capture_samples then
            if ntcfg.capture_samples ~= d.tcfg.capture_samples then
                if not ntcfg.capture_samples then
                    d.capture = nil
                elseif ntcfg.capture_samples < d.tcfg.capture_samples then -- truncate
                    for i=ntcfg.capture_samples + 1, d.tcfg.capture_samples do
                        d.capture.success.items[i]  = nil
                        d.capture.errors.items[i]   = nil
                        d.capture.success.idx       = 1
                        d.capture.errors.idx        = 1
                    end
                end
            end
        elseif ntcfg and ntcfg.capture_samples then
            d.capture = new_capture_table()
        end
        d.tcfg = ntcfg
    else
        for k, v in pairs(d) do
            path[#path + 1] = k
            reload_tcfg(v, path)
            table.remove(path)
        end
    end
end


local function diagnostic_update(ns, diag)
    local de = read_message("Fields[DecodeError]") or "<none>"
    local ts = diag[de]
    if not ts then
        ts = sats.new(TS_ROWS, SEC_IN_MINUTE * 1e9)
        diag[de] = ts
    end
    ts:add(ns, 1)
end


local function capture(d, success)
    if not d.capture then return end

    local t
    local s
    if success then
        t = d.capture.success
        s = read_message("Fields[submission]")
        if not s then return end
    else
        t = d.capture.errors
        s = read_message("Fields[DecodeErrorDetail]") or ""
    end
    if not s:match("^{") then s = string.format('"%s"', escape_json(s)) end
    t.items[t.idx] = s
    t.flag = false
    t.idx = t.idx + 1
    if t.idx > d.tcfg.capture_samples then
        t.idx = 1
    end
end


local function create_leaf(ns, tcfg)
    local t = {
        duplicates  = sats.new(TS_ROWS, SEC_IN_MINUTE * 1e9), -- duplicates removed by ingestion
        errors      = sats.new(TS_ROWS, SEC_IN_MINUTE * 1e9), -- error count
        success     = sats.new(TS_ROWS, SEC_IN_MINUTE * 1e9), -- success count
        created     = ns,
        gapc        = 0,    -- count of the gap between data rows
        gapq        = p2.quantile(0.99),
        diagnostics = {},   -- error message analysis
        tcfg        = tcfg, -- alerting threshold configuration
    }
    if tcfg.capture_samples then
        t.capture = new_capture_table()
    end
    return t
end


if hierarchy_size == 0 then
    local os = require "os"
    data = create_leaf(os.time() * 1e9, thresholds)
end


local function telemetry_ignore()
    local os = require "os"
    local l  = require "lpeg";l.locale(l)

    local grammar = l.Ct(
        l.Cg(l.digit * l.digit * l.digit * l.digit , "year")
        * l.Cg(l.digit * l.digit , "month")
        * l.Cg(l.digit * l.digit , "day")
        * l.Cg(l.digit^-2, "hour")
        * l.Cg(l.digit^-2, "min")
        * l.Cg(l.digit^-2, "sec")
        ) / os.time * l.P(-1)

    return function ()
        local ns = read_message("Timestamp")
        local bid = read_message("Fields[appBuildId]") or ""
        local bts = grammar:match(bid) or 0
        if ns / 1e9 - bts > 90 * 86400 then -- only monitor recent data
            return nil
        end
        return ns
    end
end


local path = {}
local ignore
if read_config("telemetry") then
    ignore = telemetry_ignore()
else
    ignore = function () return read_message("Timestamp") end
end


function process_message()
    local ns = ignore()
    if not ns then return 0 end

    local d  = data
    for x=1, hierarchy_size do
        local k = hierarchy[x]() or "Other"
        path[x] = k
        local t = d[k]
        if not t then
            if x == hierarchy_size then
                t = create_leaf(ns, get_tcfg(path))
            else
                t = {}
            end
            d[k] = t
        end
        d = t
    end

    local mtype = read_message("Type")
    if mtype:match("error$") then
        d.errors:add(ns, 1)
        diagnostic_update(ns, d.diagnostics)
        capture(d, false)
    elseif mtype:match("duplicate$") then
        d.duplicates:add(ns, 1)
    else
        d.success:add(ns, 1)
        capture(d, true)
    end
    return 0
end


local function diagnostic_prune(ns, diag)
    for k, v in pairs(diag) do
        if not v:get(ns) then v:add(ns, 0) end
        local _, cnt = v:stats(nil, TS_ROWS)
        if cnt == 0 then diag[k] = nil end
    end
end


local ingestion_inactivity_template = [[
No new valid data has been seen in %d minutes

Stats for the Last Hour
=======================
Submissions       : %d
Minutes with data : %d
Quantile data gap : %g
]]
local function alert_check_inactivity(name, d, ns, vsum, vcnt, gap)
    local iato = d.tcfg.inactivity
    if not iato
    or vcnt == 0
    or ns - d.created <= TS_ROWS * 60e9
    or alert.throttled(name) then
        return false
    end

    if iato == 0 then
        if gap ~= gap then return end -- NaN, no estimate yet
        iato = math.ceil((gap + 1) * 5)
        if iato >= TS_ROWS then return end -- data is too sporadic, don't monitor
    end

    if d.gapc == iato then
        local msg = string.format(ingestion_inactivity_template, iato, vsum, vcnt, gap)
        if not d.alert_ia and alert.send(name, "inactivity timeout", msg) then
            d.alert_ia = true
            return true
        end
    end
    return false
end


local function diagnostic_dump(diag)
    local t   = {}
    local idx = 0
    for k, v in pairs(diag) do
        local sum, _ = v:stats(nil, TS_ROWS)
        idx = idx + 1
        t[idx] = string.format("%d\t%s", sum, k)
    end
    table.sort(t, function(a, b) return tonumber(a:match("^%d+")) > tonumber(b:match("^%d+")) end)
    return table.concat(t, "\n")
end


local ingestion_error_template = [[
Ingestion Data for the Last Hour
================================
valid            : %d
error            : %d
percent_error    : %g
max_percent_error: %g

Diagnostic (count/error)
========================
%s
]]
local function alert_check_ingestion_error(name, d, vsum, esum)
    if vsum < 1000 and esum < 1000 then return false end
    local mpe = d.tcfg.ingestion_error
    if not mpe or alert.throttled(name) then return false end

    local pe  = esum / (vsum + esum) * 100
    if pe > mpe then
        local data = diagnostic_dump(d.diagnostics)
        local top_ie = string.match(data, "^%d+\t([^\n]+)")
        if d.last_top_ie ~= top_ie then
            d.last_top_ie = top_ie
            local msg = string.format(ingestion_error_template, vsum, esum, pe, mpe, data)
            return alert.send(name, "ingestion error", msg)
        end
    end
    return false
end

local duplicate_template = [[
Duplicate Data for the Last Hour
================================
unique               : %d
duplicate            : %d
percent_duplicate    : %g
max_percent_duplicate: %g
]]
local function alert_check_duplicates(name, d, vsum, dsum)
    local mdp = d.tcfg.duplicates
    if not mdp
    or vsum < 1000 and dsum < 1000
    or alert.throttled(name, 1440) then -- more informational, limit to once  day
        return false
    end

    local dp = dsum / (vsum + dsum) * 100
    if dp > mdp then
        if alert.send(name, "duplicate",
                      string.format(duplicate_template, vsum, dsum, dp, mdp)) then
            return true
        end
    end
    return false
end


local function output_leaf(ns, summary, captures, d, path)
    if #path == hierarchy_size then
        -- always advance the time series buffers
        if not d.success:get(ns) then
            d.success:add(ns, 0)
            d.gapc = d.gapc + 1
        else
            for i=0, d.gapc do
                d.gapq:add(i)
            end
            d.gapc = 0
            d.alert_ia = false
        end
        if not d.errors:get(ns) then d.errors:add(ns, 0) end
        if not d.duplicates:get(ns) then d.duplicates:add(ns, 0) end
        diagnostic_prune(ns, d.diagnostics)

        local vsum, vcnt = d.success:stats(nil, TS_ROWS)
        local esum, ecnt = d.errors:stats(nil, TS_ROWS)
        local dsum, dcnt = d.duplicates:stats(nil, TS_ROWS)
        local gap = d.gapq:estimate(2)
        summary[#summary + 1] = string.format("%s\t%d\t%d\t%d\t%g\t%d\t%d\t%d\t%d\n",
                                     table.concat(path, "\t"), vsum, vcnt,
                                     d.gapc, gap, esum, ecnt, dsum, dcnt)

        if d.tcfg then
            local name = table.concat(path, "_")
            alert_check_inactivity(name, d, ns, vsum, vcnt, gap)
            alert_check_ingestion_error(name, d, vsum, esum)
            alert_check_duplicates(name, d, vsum, dsum)
            if d.capture then
                captures[#captures + 1] = string.format('"%s":{"success":[%s],\n"errors":[%s]}', name,
                                                        table.concat(d.capture.success.items, ",\n"),
                                                        table.concat(d.capture.errors.items, ",\n"))
                d.capture.success.flag = true
                d.capture.errors.flag = true
            end
        end
    else
        for k, v in pairs(d) do
            path[#path + 1] = k
            output_leaf(ns, summary, captures, v, path)
            table.remove(path)
        end
    end

end


local startup = true
function timer_event(ns, shutdown)
    if shutdown then return end
    if startup then
        reload_tcfg(data, {}) -- propagate threshold changes
        startup = false
    end

    local summary = {title}
    local captures = {}
    output_leaf(ns - 60e9, summary, captures, data, {})
    inject_payload("tsv", "summary", table.concat(summary, "\n"))
    inject_payload("json", "captures", "{\n", table.concat(captures, ",\n"), "}\n")
end

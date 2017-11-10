-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Logging Ingestion Error Monitor

Monitors ingestion errors on all inputs.

## Sample Configuration
```lua
filename = 'moz_logging_ingestion_error_monitor.lua'
message_matcher = "TRUE"
ticker_interval = 60
preserve_data = true
memory_limit = 1024 * 1024 * 64
timer_event_inject_limit = 100

alert = {
  disabled = false,
  prefix = true,
  throttle = 90,
  modules = {
    email = {recipients = {"trink@mozilla.com"}},
  },
  thresholds = {
    -- ["input.bastion_systemd_sshd"] = {inactivity_timeout = 60, percent = 0.5} -- a timeout of 60 or more disables the check as the alert window is only one hour
    _default_ = {inactivity_timeout = 5, -- minutes percent = 0.5} -- if not specified the default is no monitoring
  }
}
```
--]]
_PRESERVATION_VERSION = 0

require "circular_buffer"
require "os"
require "string"
require "table"
local alert = require "heka.alert"
local stats = require "lsb.stats"

local SEC_IN_MINUTE     = 60
local HOURS_IN_DAY      = 24
local HOURS_IN_WEEK     = 168
local MINS_IN_HOUR      = 60
local SEC_IN_HOUR       = SEC_IN_MINUTE * MINS_IN_HOUR
local MINS_IN_DAY       = MINS_IN_HOUR * HOURS_IN_DAY
local ROWS              = MINS_IN_DAY * 8 + 1 -- add an extra row to compensate for the currently active minute
local CREATED           = 1
local INGESTED          = 2
local ERROR             = 3

local cnt = 0
for k,v in pairs(alert.thresholds) do
    assert(type(v.inactivity_timeout) == "number", "inactivity_timeout must be a number")
    assert(type(v.percent) == "number", "percent must be a number")
    cnt = cnt + 1
end
assert(cnt > 0, "at least one alert threshold must be set")

inputs = {}
local function get_input(logger, rows, spr)
    logger = logger:match("^([^|]+)")
    local l = inputs[logger]
    if not l then
        local cb = circular_buffer.new(ROWS, 3, SEC_IN_MINUTE)
        cb:set_header(CREATED, "created")
        cb:set_header(INGESTED, "ingested")
        cb:set_header(ERROR, "error")
        l = {cb, {}}
        inputs[logger] = l
    end
    return l
end


local function diagnostic_update(ns, diags)
    if not diags then return end

    local de = read_message("Payload") or "<none>"
    local cb = diags[de]
    if not cb then
        cb = circular_buffer.new(MINS_IN_HOUR + 1, 1, SEC_IN_MINUTE)
        diags[de] = cb
    end
    cb:add(ns, 1, 1)
end


function process_message()
    local l = get_input(read_message("Logger"))

    local cns = os.time() * 1e9
    if read_message("Type") == "error" then
        l[1]:add(cns, ERROR, 1)
        diagnostic_update(cns, l[2])
    else
        local ns = read_message("Timestamp")
        l[1]:add(ns, CREATED, 1)
        l[1]:add(cns, INGESTED, 1)
    end
    return 0
end


local function diagnostic_dump(diags)
    local t   = {}
    local idx = 0
    for k, v in pairs(diags) do
        local val, _ = stats.sum(v:get_range(1))
        idx = idx + 1
        t[idx] = string.format("%d\t%s", val, k)
    end
    table.sort(t, function(a, b) return tonumber(a:match("^%d+")) > tonumber(b:match("^%d+")) end)
    return table.concat(t, "\n")
end


local function diagnostic_prune(ns, diags)
    for k, v in pairs(diags) do
        if not v:get(ns, 1) then
            v:add(ns, 1, 0/0) -- always advance the buffer
        end
        local _, cnt = stats.sum(v:get_range(1))
        if cnt == 0 then diags[k] = nil end
    end
end


local function inactivity_alert(ns, th, k, vcnt, cb, e)
    if vcnt == 0 then return false end

    local iato = th.inactivity_timeout
    if MINS_IN_HOUR - vcnt > iato then
        local _, cnt = stats.sum(cb:get_range(INGESTED, e - ((iato - 1) * 60e9))) -- include the current minute
        if cnt == 0 then
            if alert.send(k, "inactivitiy timeout",
                          string.format("No new valid data has been seen in %d minutes\n\ngraph: %s\n",
                                        iato, alert.get_dashboard_uri(k))) then
                cb:annotate(ns, INGESTED, "alert", "inactivitiy timeout")
            end
            return true
        end
    end
    return false
end


local ingestion_error_template = [[
Ingestion Data for the Last Hour
================================
ingested         : %d
error            : %d
percent_error    : %g
max_percent_error: %g

graph: %s

Diagnostic (count/error)
========================
%s
]]

function timer_event(ns, shutdown)
    for k, v in pairs(inputs) do
        local cb = v[1]
        if not cb:get(ns, 1) then
            cb:add(ns, 1, 0/0) -- always advance the buffer/graphs
        end

        local diags = v[2]
        diagnostic_prune(ns, diags)

        local th = alert.get_threshold(k)
        if th and not alert.throttled(k) then
            local e = cb:current_time() - 60e9 -- exclude the current minute
            local s = e - ((MINS_IN_HOUR - 1) * 60e9)
            local array = cb:get_range(INGESTED, s, e)
            local isum, vcnt = stats.sum(array)
            if not inactivity_alert(ns, th, k, vcnt, cb, e) then
                array = cb:get_range(ERROR, s, e)
                local esum = stats.sum(array)
                if isum > 1000 or esum > 1000 then
                    local pe  = esum / (isum + esum) * 100
                    if pe > th.percent then
                        if alert.send(k, "ingestion error",
                                      string.format(ingestion_error_template, isum, esum, pe,
                                                    th.percent, alert.get_dashboard_uri(k),
                                                    diagnostic_dump(diags))) then
                            cb:annotate(ns, ERROR, "alert", string.format("%.4g%%", pe))
                        end
                    end
                end
            end
        end
        inject_payload("cbuf", k, cb)
    end
end

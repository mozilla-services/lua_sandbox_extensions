-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Logging Ingestion Error Monitor

Monitors ingestion errors on all inputs, with optional inactivity and latency
alerts.

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
    -- ["<input_name>"] = {
        -- percent            - required (0 - 100), maximum percent error before alerting
        -- inactivity_timeout - optional (1 - 3600 seconds), time with no data before alerting
           -- rounded up to the nearest minute; specified in seconds to keep the units consistent
        -- latency            - optional (1 - 3600 seconds), median latency before alerting
    -- },
    ["*"] = { -- if not specified the default is no monitoring
        percent = 0.5,
        inactivity_timeout = 300,
        latency = 60
    }
  }
}
```
--]]
_PRESERVATION_VERSION = (read_config("preservation_version") or 0) + 1

require "circular_buffer"
require "math"
require "os"
require "string"
require "table"
require "streaming_algorithms.p2"
local alert = require "heka.alert"
local stats = require "lsb.stats"

local SEC_IN_MINUTE     = 60
local HOURS_IN_DAY      = 24
local MINS_IN_HOUR      = 60
local SEC_IN_HOUR       = SEC_IN_MINUTE * MINS_IN_HOUR
local MINS_IN_DAY       = MINS_IN_HOUR * HOURS_IN_DAY
local ROWS              = MINS_IN_DAY
local CREATED           = 1
local INGESTED          = 2
local ERROR             = 3
local LATENCY           = 4

local cnt = 0
for k,v in pairs(alert.thresholds) do
    assert(type(v.percent) == "number"
           and v.percent >= 0
           and v.percent <= 100, "percent must be a number (0 - 100)")

    local t = type(v.inactivity_timeout)
    assert(t == "nil" or t == "number"
           and v.inactivity_timeout > 0
           and v.inactivity_timeout <= 3600, "inactivity_timeout must be a number (1 - 3600 seconds)")
    v.inactivity_timeout = math.ceil(v.inactivity_timeout / 60)

    t = type(v.latency)
    assert(t == "nil" or t == "number"
           and v.latency > 0
           and v.latency <= 3600, "latency must be a number (1 - 3600 seconds)")
    cnt = cnt + 1
end
assert(cnt > 0, "at least one alert threshold must be set")

inputs = {}
local function get_input(logger, rows, spr)
    logger = logger:match("^([^|]+)")
    local l = inputs[logger]
    if not l then
        local cb = circular_buffer.new(ROWS, 4, SEC_IN_MINUTE)
        cb:set_header(CREATED, "created")
        cb:set_header(INGESTED, "ingested")
        cb:set_header(ERROR, "error")
        cb:set_header(LATENCY, "latency", "s")
        l = {cb, {}, streaming_algorithms.p2.quantile(0.5)}
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
        l[3]:add(cns - ns)
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
local function error_alert(ns, th, k, cb, s, e)
    local array = cb:get_range(INGESTED, s, e)
    local isum, vcnt = stats.sum(array)
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
    return vcnt
end


local function inactivity_alert(ns, th, k, vcnt, cb, e)
    local iato = th.inactivity_timeout
    if vcnt == 0 or iato == 0 then return end

    if MINS_IN_HOUR - vcnt > iato then
        local _, cnt = stats.sum(cb:get_range(INGESTED, e - ((iato - 1) * 60e9))) -- include the current minute
        if cnt == 0 then
            if alert.send(k, "inactivitiy timeout",
                          string.format("No new valid data has been seen in %d minutes\n\ngraph: %s\n",
                                        iato, alert.get_dashboard_uri(k))) then
                cb:annotate(ns, INGESTED, "alert", "inactivitiy timeout")
            end
        end
    end
end


function timer_event(ns, shutdown)
    for k, v in pairs(inputs) do
        local cb = v[1]
        local latency = v[3]:estimate(2) / 1e9
        v[3]:clear()
        cb:set(ns, LATENCY, latency)

        local diags = v[2]
        diagnostic_prune(ns, diags)

        local th = alert.get_threshold(k)
        if th and not alert.throttled(k) then
            local e = cb:current_time() - 60e9 -- exclude the current minute
            local s = e - ((MINS_IN_HOUR - 1) * 60e9)
            local vcnt = error_alert(ns, th, k, cb, s, e)
            inactivity_alert(ns, th, k, vcnt, cb, e)
            if th.latency > 0 and latency > th.latency then
                local err = string.format("Median latency: %d", latency)
                if alert.send(k, "latency error", err) then
                    cb:annotate(ns, LATENCY, "alert", err)
                end
            end
        end
        inject_payload("cbuf", k, cb)
    end
end

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry docType Error Ratio Monitor

Monitors the error/total ratio of each docType ping with a secondary check to
identify a data outage.

## Sample Configuration
```lua
filename = 'moz_telemetry_doctype_error_ratio_monitor.lua'
message_matcher = 'Type == "telemetry" || Type == "telemetry.error"'
ticker_interval = 60
preserve_data = true

alert = {
  disabled = false,
  prefix = true,
  throttle = 90,
  modules = {
    email = {recipients = {"trink@mozilla.com", "mreid@mozilla.com", "whd@mozilla.com", "rvitillo@mozilla.com"}},
  },
  thresholds = {
    ["main"] = {
      max_error_ratio     = 0.005,
      inactivity_timeout  = 5,
    },
    ["core"] = {
      max_error_ratio     = 0.001,
      inactivity_timeout  = 5,
    },
    ["crash"] = {
      max_error_ratio     = 0.01,
      inactivity_timeout  = 5,
    },
    ["saved-session"] = {
      max_error_ratio     = 0.02,
      inactivity_timeout  = 5,
    },
    ["testpilot"] = {
      max_error_ratio     = 0.01,
      inactivity_timeout  = 5,
    },
    ["testpilottest"] = {
      max_error_ratio     = 0.01,
      inactivity_timeout  = 5,
    },
    _invalid_ = {}, -- disabled
    _default_ = {}, -- disabled
  }
}
```
--]]

require "circular_buffer"
require "string"
require "table"

local stats = require "lsb.stats"
local alert = require "heka.alert"

last_output = 0
output_size = 0
output   = {}
doctypes = {}

local te_inject_limit = read_config("timer_event_inject_limit")

local VALID         = 1
local ERROR         = 2
local NUM_COLS      = ERROR
local SEC_PER_ROW   = 60
local ALERT_WINDOW  = 60


local function diagnostic_dump(diag)
    local t   = {}
    local idx = 0
    for k, v in pairs(diag) do
        local val, _ = stats.sum(v:get_range(1))
        idx = idx + 1
        t[idx] = string.format("%d\t%s", val, k)
    end
    table.sort(t, function(a, b) return tonumber(a:match("^%d+")) > tonumber(b:match("^%d+")) end)
    return table.concat(t, "\n")
end


local function diagnostic_prune(ns, diag)
    for k, v in pairs(diag) do
        if not v:get(ns, 1) then
            v:add(ns, 1, 0/0) -- always advance the buffer
        end
        local _, cnt = stats.sum(v:get_range(1))
        if cnt == 0 then diag[k] = nil end
    end
end


local function diagnostic_update(ns, diag)
    local de = read_message("Fields[DecodeError]") or "<none>"
    local cb = diag[de]
    if not cb then
        cb = circular_buffer.new(ALERT_WINDOW, 1, SEC_PER_ROW)
        diag[de] = cb
    end
    cb:add(ns, 1, 1)
end


local function new_cb()
    local cb = circular_buffer.new(60 * 24 * 8, NUM_COLS, SEC_PER_ROW)
    cb:set_header(VALID, "valid")
    cb:set_header(ERROR, "error")
    return cb
end


local function get_doctype(name)
    if type(name) ~= "string" or string.match(name, "[^-a-zA-Z0-9_]") then
        name = "_invalid_"
    end
    local data = doctypes[name]
    if not data then
        local threshold = alert.get_alert_threshold(name)
        if threshold.max_error_ratio then
            assert(threshold.max_error_ratio > 0 and threshold.max_error_ratio < 1,
                   name .. " max_error_ratio must be between 0 and 1")
        end
        if threshold.inactivity_timeout then
            assert(threshold.inactivity_timeout > 0 and threshold.inactivity_timeout <= 60,
                   name .. " inactivity_timeout must be 1-60")
        end
        data = {name, new_cb(), {}}
        doctypes[name] = data
        output_size = output_size + 1
        output[output_size] = data
    end
    return data
end


function process_message()
    local ns = read_message("Timestamp")
    local dt = read_message("Fields[docType]")
    local data = get_doctype(dt)
    local cb = data[2]

    local t = read_message("Type")
    if t == "telemetry" then
        cb:add(ns, VALID, 1)
    else
        diagnostic_update(ns, data[3])
        cb:add(ns, ERROR, 1)
    end
    return 0
end


local alert_template = [[
Submission Data for the Last Hour
=================================
valid submissions: %g
error submissions: %g
error ratio      : %g
max_error_ratio  : %g

graph: %s

Diagnostic (count/error)
========================
%s
]]


local function alert_check(ns, name, cb, diag)
    local threshold = alert.get_alert_threshold(name)
    local iato = threshold.inactivity_timeout
    local mer  = threshold.max_error_ratio
    if not iato and not mer or alert.throttled(name) then return end

    local e = cb:current_time() - (SEC_PER_ROW * 1e9) -- exclude the current minute
    local s = e - (SEC_PER_ROW * (ALERT_WINDOW - 1) * 1e9)
    local val, cnt = stats.sum(cb:get_range(VALID, s, e))

    if iato and ALERT_WINDOW - cnt > iato then
        local _, cnt = stats.sum(cb:get_range(VALID, e - (SEC_PER_ROW * (iato - 1) * 1e9))) -- include the current minute
        if cnt == 0 then
            if alert.send(name, "inactivitiy_timeout",
                          string.format("No new valid data has been seen in %d minutes\n\ngraph: %s\n",
                                        iato, alert.get_dashboard_uri(name))) then
                cb:annotate(ns, VALID, "alert", "inactivitiy timeout")
                return true
            end
            return false
        end
    end

    diagnostic_prune(ns, diag)

    if mer and cnt >= 10 then
        local err = stats.sum(cb:get_range(ERROR, s, e))
        local er  = err / (val + err)
        if er > mer then
            if alert.send(name, "max_error_ratio",
                          string.format(alert_template, val, err, er, mer, alert.get_dashboard_uri(name),
                                        diagnostic_dump(diag))) then
                cb:annotate(ns, VALID, "alert", string.format("%.4g exceeded %.4g", er, mer))
                return true
            end
            return false
        end
    end
    return false
end


function timer_event(ns, shutdown)
    local im_remaining  = te_inject_limit
    local graphs_output = 0
    while im_remaining > 1 and graphs_output < output_size do
        last_output = last_output + 1
        if last_output > output_size  then
            last_output = 1
        end
        local name  = output[last_output][1]
        local cb    = output[last_output][2]
        local diag  = output[last_output][3]

        if not cb:get(ns, VALID) then
            cb:add(ns, VALID, 0/0) -- always advance the buffer/graph
        end
        inject_payload("cbuf", name, cb)
        graphs_output = graphs_output + 1
        if alert_check(ns, name, cb, diag) then
            im_remaining = im_remaining - 2
        else
            im_remaining = im_remaining - 1
        end
    end
end

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Alert Module

## Sample Configuration
```lua
alert = {
    disabled = false, -- optional
    prefix   = false, -- optional prefix plugin information to the summary and detail strings
    throttle = 90,    -- optional number of minutes to wait before another alert with this ID will be sent
    modules  = {
      -- module_name = {}, -- see the heka.alert.modules_name documentation for the configuration options
      -- e.g., email = {recipients = {"foo@example.com"}},
    }
    thresholds = {
      -- alert_id = {}, -- per id alert specific configuration for an analyis plugin
    }
}

```
## Variables

* thresholds - the thresholds configuration table

## Functions

### get_dashboard_uri

Returns the URI of the dashboard output

*Arguments*
- id (string)
- extension (string/nil) - defaults to cbuf

*Return*
- URI (string)

### get_threshold

Gets the value of the threshold setting associated with the specified id. If
the id is not found the value of the '_default_' key is returned otherwise nil
is returned.

*Arguments*
- id (string)

*Return*
- threshold - configuration value

### throttled

Check if an alert is currently throttled, this is useful to avoid running
expensive tests.

*Arguments*
- id (string)
- throttle (integer, nil) - override the throttle value (nil uses the configured
  value)

*Return*
- throttled (boolean) - true if the alert is currently throttled

### send

Send an alert message

*Arguments*
- id (string) - unique id for alert throttling
- summary (string) - alert summary
- detail (string) - alert detail
- throttle (integer, nil) - override the throttle value (nil uses the configured
  value)

*Return*
- sent (boolean) - true if sent, false if throttled/disabled/empty
--]]

-- Imports
local string = require "string"
local time   = require "os".time

local error     = error
local ipairs    = ipairs
local pairs     = pairs
local pcall     = pcall
local require   = require
local type      = type

local logger    = read_config("Logger")
local hostname  = read_config("Hostname")
local pid       = read_config("Pid")

local inject_message = inject_message

local alert_cfg = read_config("alert")
assert(type(alert_cfg) == "table", "alert configuration must be a table")
assert(type(alert_cfg.modules) == "table", "alert.modules configuration must be a table")
if type(alert_cfg.thresholds) == "nil" then alert_cfg.thresholds = {} end
assert(type(alert_cfg.thresholds) == "table", "alert.thresholds configuration must be nil or a table")

alert_cfg.throttle = alert_cfg.throttle or 90
assert(type(alert_cfg.throttle) == "number" and alert_cfg.throttle > 0, "alert.throttle configuration must be a number > 0 ")
alert_cfg.throttle = alert_cfg.throttle * 60

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local msg = {
    Type = "alert",
    Payload = "",
    Severity = 1,
    Fields = {
        {name = "id"        , value = ""},
        {name = "summary"   , value = ""},
    }
}

-- load alert specific configuration settings into the message
if not alert_cfg.disabled then
    local empty = true
    for k,v in pairs(alert_cfg.modules) do
        local ok, mod = pcall(require, "heka.alert." .. k)
        if ok then
            for i,v in ipairs(mod) do
                msg.Fields[#msg.Fields + 1] = v;
            end
        else
            error(mod)
        end
        empty = false
    end
    if empty then error("No alert modules were specified") end
end

local alert_times = {}

local function normalize(s)
    return string.gsub(s, "[^%w%.]", "_")
end


function get_dashboard_uri(id, ext)
    if not ext or ext == "cbuf" then
        return string.format("https://%s/dashboard_output/graphs/%s.%s.html",
                             hostname, normalize(logger), normalize(id))
    else
        return string.format("https://%s/dashboard_output/%s.%s.%s",
                             hostname, normalize(logger), normalize(id), normalize(ext))
    end
end


thresholds = alert_cfg.thresholds -- expose the entire table
function get_threshold(id)
    local at = alert_cfg.thresholds[id]
    if not at then
        at = alert_cfg.thresholds._default_
    end
    return at
end


function throttled(id, throttle)
    if type(throttle) == "number" then
        throttle = throttle * 60
    else
        throttle = alert_cfg.throttle
    end

    local time_t = time()
    local at = alert_times[id]
    if not at or throttle == 0 or time_t - at > throttle then
        return false
    end
    return true
end


function send(id, summary, detail, throttle)
    if alert_cfg.disabled or not summary or summary == "" or throttled(id, throttle) then
        return false
    end

    msg.Fields[1].value = id
    if alert_cfg.prefix then
        msg.Fields[2].value = string.format("Hindsight [%s#%s] - %s", logger, id, summary)
        msg.Payload         = string.format("Hostname: %s\nPid: %d\n\n%s\n", hostname, pid, detail)
    else
        msg.Fields[2].value = summary
        msg.Payload         = detail
    end

    inject_message(msg)
    alert_times[id] = time()
    return true
end

return M

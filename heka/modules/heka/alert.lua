-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Alert Module

Sends alert messages for consumption by the alert output sandbox.

Plugins that make use of this module require a valid alert configuration.

At a high level there are two modes of operation for this module, static alerting and
alerting with a lookup module. The mode of operation is dependent on if the lookup configuration
parameter is set, and the sub-modules specified in the modules configuration.

Static operating mode will always send alerts to the same destination. This mode is useful if
a plugin does not need to modify a destination for an alert. Static operating mode is set
by not setting a lookup plugin, and by specifying the required Heka alert modules in the modules
configuration.

If the lookup parameter is set, it should be set to the name of a valid alerting lookup
module. In this mode, the get_message function of the lookup plugin will be called with
lookup data, and the lookup plugin will make a decision on where to route the alert and return
an alert message for submission. In lookup mode, the modules configuration should include only
a configuration for the desired lookup module.

## Lookup Data

When using a lookup module, the plugin calling the alert.send function needs to provide
lookup data for the lookup plugin to make a decision on alert routing.

```lua
-- example lookup data
local ldata = {
    sendglobal = true,      -- The alert should be sent to a global alerting destination (nil/false for off)
    senderror  = false,     -- Don't send the alert to any error destination (nil/false for off)
    senduser   = true,      -- The alert should be sent directly to the identity (nil/false for off)
    subject    = "userid"   -- This alert is for this specific identity (nil for none)
}
-- send the alert, specifying our lookup data
alert.send("myalert", subject, payload, 0, ldata)
```

Any combination of parameters is valid and it is up to the configured lookup module to determine
how to route the alert.

## Sample Configuration
```lua
alert = {
    lookup   = nil,   -- optional, if specified a string indicating a heka alerting lookup module
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
the id is not found the value of the '*' key is returned otherwise nil
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

### has_lookup

Return true if the alert module has a lookup function associated with it.

*Arguments*
- None

*Return*
- func (boolean) - true if alert module has lookup function

### send

Send an alert message

*Arguments*
- id (string) - unique id for alert throttling
- summary (string) - alert summary
- detail (string) - alert detail
- throttle (integer, nil) - override the throttle value (nil for configured, 0 for none)
- ldata (table, nil) - lookup data table, used if module is in lookup mode

*Return*
- sent (boolean) - true if sent, false if throttled/disabled/empty
--]]

local string = require "string"
local time   = require "os".time

local error             = error
local ipairs            = ipairs
local pairs             = pairs
local pcall             = pcall
local require           = require
local type              = type
local inject_message    = inject_message

local logger    = read_config("Logger")
local hostname  = read_config("Hostname")
local pid       = read_config("Pid")

local lfunc

local alert_cfg = read_config("alert")
assert(type(alert_cfg) == "table", "alert configuration must be a table")
assert(type(alert_cfg.modules) == "table", "alert.modules configuration must be a table")

if alert_cfg.lookup then
    assert(type(alert_cfg.lookup) == "string", "alert.lookup configuration must be a string")
    local ok, lmod = pcall(require, "heka.alert." .. alert_cfg.lookup)
    if not ok then error(lmod) end
    lfunc = lmod.get_message
    assert(type(lfunc) == "function", "invalid alert lookup module specified")
end

if type(alert_cfg.thresholds) == "nil" then alert_cfg.thresholds = {} end
assert(type(alert_cfg.thresholds) == "table", "alert.thresholds configuration must be nil or a table")

alert_cfg.throttle = alert_cfg.throttle or 90
assert(type(alert_cfg.throttle) == "number" and alert_cfg.throttle >= 0, "alert.throttle configuration must be a number >= 0")
alert_cfg.throttle = alert_cfg.throttle * 60

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local msg
if not lfunc then
    msg = {
        Type = "alert",
        Payload = "",
        Severity = 1,
        Fields = {
            {name = "id"        , value = ""},
            {name = "summary"   , value = ""},
        }
    }
end

-- load alert specific configuration settings into the message if not in lookup mode
if not alert_cfg.disabled and not lfunc then
    local empty = true
    for k,v in pairs(alert_cfg.modules) do
        local ok, mod = pcall(require, "heka.alert." .. k)
        if ok then
            if mod.get_message then
                error("cannot use lookup module without lookup configuration")
            end
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
        at = alert_cfg.thresholds["*"] or alert_cfg.thresholds._default_
    end
    return at
end


function throttled(id, throttle)
    if type(throttle) == "number" then
        throttle = throttle * 60
    else
        throttle = alert_cfg.throttle
    end
    if throttle == 0 then return false end

    local time_t = time()
    local at = alert_times[id]
    if not at or throttle == 0 or time_t - at > throttle then
        return false
    end
    return true
end


function has_lookup()
    if lfunc then return true end
    return false
end

function send(id, summary, detail, throttle, ldata)
    if alert_cfg.disabled or not summary or summary == "" or throttled(id, throttle) then
        return false
    end

    if not lfunc then
        msg.Fields[1].value = id
        if alert_cfg.prefix then
            msg.Fields[2].value = string.format("Hindsight [%s#%s] - %s", logger, id, summary)
            msg.Payload         = string.format("Hostname: %s\nPid: %d\n\n%s\n", hostname, pid, detail)
        else
            msg.Fields[2].value = summary
            msg.Payload         = detail
        end
    else
        if not ldata then error("cannot call lookup function with no lookup data") end
        msg = lfunc(id, summary, detail, ldata)
    end

    if msg then inject_message(msg) end
    alert_times[id] = time()
    return true
end

return M

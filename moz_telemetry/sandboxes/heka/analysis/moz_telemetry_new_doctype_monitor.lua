
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry New DocType Monitor

Monitors the telemetry stream for new document types and alerts if 
they meet a volume threshold.

## Sample Configuration
```lua
filename = "moz_telemetry_new_doctype_monitor.lua"
message_matcher = "Type == 'telemetry'"
ticker_interval = 60
preserve_data = true
threshold = 100

-- Maintained in the puppet repository: https://github.com/mozilla-services/puppet-config/blob/master/pipeline/yaml/app/pipeline.yaml#L78
known_doctypes = {
    "idle-daily", "saved-session", "android-anr-report", "ftu", "loop",
    "flash-video", "main", "activation", "deletion", "crash", "uitour-tag",
    "heartbeat", "core", "b2g-installer-device", "b2g-installer-flash",
    "advancedtelemetry", "appusage", "testpilot", "testpilottest",
    "malware-addon-states", "sync", "outofdate-notifications-system-addon",
    "tls-13-study", "shield-study", "shield-study-addon", "shield-study-error",
    "system-addon-deployment-diagnostics", "disableSHA1rollout", "tls-13-study-v1",
    "tls-13-study-v2", "tls-13-study-v3", "tls13-middlebox-repetition",
    "tls13-middlebox-testing", "modules", "certificate-checker",
    "flash-shield-study", "deployment-checker", "anonymous", "focus-event",
    "new-profile", "health", "update", "tls13-middlebox-alt-server-hello-1",
    "first-shutdown", "tls13-middlebox-ghack", "mobile-event",
    "tls13-middlebox-draft22"
}

alert = {
  disabled = false,
  prefix = false,
  threshold = 90,  -- one alert every 90 minutes
  modules = {
    email = {recipients = {"amiyaguchi@mozilla.com"}},
  }
}
```
--]]

_PRESERVATION_VERSION = 0

local alert = require "heka.alert"
local table = require "table"

-- Helper function to generate a set
function Set(list)
    local set = {}
    for _, l in ipairs(list) do set[l] = true end
    return set
end

local known_doctypes = Set(read_config("known_doctypes"))

discovered = {}     -- Preserved doctypes that have been discovered
counts = {}         -- Count of the candidate doctypes
refresh_cycles = 0  -- Number of timer events since the last refresh

local threshold = read_config("threshold")
local ticker_interval = read_config("ticker_interval")
local seconds_per_day = 86400


function process_message()
    local dt = read_message("Fields[docType]")
    if type(dt) ~= "string" then dt = "invalid" end

    -- Count the document if its below the daily threshold
    if not (known_doctypes[dt] or discovered[dt]) then
        counts[dt] = (counts[dt] or 0) + 1
    end

    return 0
end

function timer_event(ns, shutdown)
    -- Send an alert when the count reaches a certain threshold
    if not alert.throttled("new_doctype") then
        local keys = {}
        for dt, count in pairs(counts) do
            if count >= threshold then
                keys[#keys+1] = dt
                counts[dt] = nil
                discovered[dt] = true
            end
        end
        if #keys > 0 then
            local body = table.concat(keys, "\n")
            alert.send("new_doctype", "alert: new ping types detected", body)
        end
    end

    if refresh_cycles >= seconds_per_day / ticker_interval then
        refresh_cycles = 0
        -- make sure to alert in the next cycle if the messages have been throttled
        for dt, count in pairs(counts) do
            if count < threshold then counts[dt] = nil end
        end
    else
        refresh_cycles = refresh_cycles + 1
    end
end

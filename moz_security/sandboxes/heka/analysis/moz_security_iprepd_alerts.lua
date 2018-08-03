-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
#  Mozilla Security iprepd Reputation Alerts

Monitors iprepd log events and generates notices when the reputation of a
given IP falls below certain thresholds (<=75, <=50, <=25).

The alerting key is generated based on the passed threshold and the IP address,
to suppress further notifications about changes within a given window.

If enable_metrics is true, the module will submit metrics events for collection by the metrics
output sandbox. Ensure process_message_inject_limit is set appropriately, as if enabled process_event
will submit up to 2 messages (the alert, and the metric event).

## Sample Configuration
```lua
filename = "moz_security_tb_alerts.lua"
message_matcher = "Type =~ 'logging.iprepd.app.docker'%"
ticker_interval = 0
process_message_inject_limit = 1

prefix = "hhfxa" -- define a prefix to include with the alert messages

-- module makes use of alert output and needs a valid alert configuration
alert = {
    modules = { }
}

-- enable_metrics -- optional, if true enable secmetrics submission
```
--]]
--
require "string"

local alert = require "heka.alert"

local prefix = read_config("prefix") or error("prefix must be configured")

local secm
if read_config("enable_metrics") then
    secm = require "heka.secmetrics".new()
end

local pfix75        = "|75"
local pfix50        = "|50"
local pfix25        = "|25"

function process_message()
    local ip            = read_message("Fields[ip]")
    local reputation    = read_message("Fields[reputation]")
    local msg           = read_message("Fields[msg]")
    local exception     = read_message("Fields[exception]")
    local violation     = read_message("Fields[violation]") or "unknown"
    if not ip or not reputation or not msg then return 0 end

    local isviolation = false
    -- we only care about a couple types of messages here, so make sure that's what we
    -- have
    if msg == "violation applied" then
        isviolation = true
    elseif msg ~= "reputation set" then return 0 end

    if secm then
        if isviolation then secm:inc_accumulator("total_count") end
    end

    if exception then
        if secm and isviolation then
            secm:inc_accumulator("violation_exceptions")
            secm:send()
        end
        return 0
    end

    local k = ip
    -- also set k to be used as an alert key to throttle further notification of adjustments
    -- in this window
    if secm and isviolation then
        secm:inc_accumulator("violation_applied")
        secm:inc_accumulator("violation_count_" .. violation)
    end
    if reputation <= 25 then
        k = k .. pfix25
        if secm then secm:inc_accumulator("violation_25") end
    elseif reputation <= 50 then
        k = k .. pfix50
        if secm then secm:inc_accumulator("violation_50") end
    elseif reputation <= 75 then
        k = k .. pfix75
        if secm then secm:inc_accumulator("violation_75") end
    else
        if secm then secm:send() end
        return 0
    end

    local t = string.format("[%s] iprepd adjust %s to %d (set key %s)", prefix, ip, reputation, k)
    if isviolation then
        t = t .. string.format(" on violation %s", violation)
    else
        t = t .. " directly applied"
    end
    alert.send(k, t, t)

    if secm and isviolation then
        secm:send()
    end

    return 0
end


function timer_event()
    -- no op
end

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Security Metrics Output Plugin

This output module collects metrics generated using the secmetrics Heka module,
aggregates them, and outputs them based on the configured ticker interval.

If using email based output via the email_recipient option, ensure you have
a valid email alert configuration. The email functionality in this sandbox makes
use of the existing code present for email based alerting.

## Sample Configuration
```lua
filename = "moz_security_metrics.lua"
message_matcher = "Type == 'secmetrics'"
ticker_interval = 28800

-- debug = false -- optional, if set emit aggregated stats in debug log

-- email_recipient = "riker@mozilla.com" -- optional, if set emit metrics to specified recipient
-- alert = { modules = { email = { ... } } } -- optional, required if email_recipient is set
```
--]]

require "cjson"

local ostime = require "os".time
local flr    = require "math".floor

local debug         = read_config("debug")
local recipient     = read_config("email_recipient")
local cephost       = read_config("Hostname")

_PRESERVATION_VERSION = read_config("preservation_version") or 0

z       = {}       -- global, reload on startup
startts = ostime() -- global, reload on startup

local malert
if recipient then
    malert = require "alert.email"
end

local function fold(endts)
    local ret = {}
    for k,v in pairs(z) do
        ret[k] = {}
        for x,y in pairs(v.accumulators) do
            ret[k][x] = y
        end
        for x,y in pairs(v.uniqitems) do
            local cnt = 0
            for l,w in pairs(y) do
                cnt = cnt + 1
            end
            assert(not ret[k][x], "collision in metric name for " .. k)
            ret[k][x] = cnt
        end
    end
    ret.startts = startts
    ret.endts = endts
    return ret
end

function process_message()
    local buf = read_message("Payload")
    if not buf then return 0 end
    local t = cjson.decode(buf)

    local x = z[t.identifier]
    if not x then
        x = {
            accumulators    = {},
            uniqitems       = {}
        }
        z[t.identifier] = x
    end

    for k,v in pairs(t.accumulators) do
        if not x.accumulators[k] then
            x.accumulators[k] = v
        else
            x.accumulators[k] = x.accumulators[k] + v
        end
    end

    for k,v in pairs(t.uniqitems) do
        if not x.uniqitems[k] then
            x.uniqitems[k] = v
        else
            for l,w in pairs(t.uniqitems[k]) do
                x.uniqitems[k][l] = w
            end
        end
    end

    return 0
end

function timer_event(ns)
    local cts = flr(ns / 1e9)
    local c = cjson.encode(fold(cts))
    if debug then
        print(c)
    else
        local summary = "secmetrics summary from " .. cephost
        if malert then -- generate email using email alert module
            local alertbuf = {
                Type        = "alert",
                Payload     = c,
                Severity    = 5,
                Fields = {
                    { name = "id", value = { c } },
                    { name = "summary", value = { summary } },
                }
            }
            local _, serr = pcall(malert.send, alertbuf, { recipients = recipient })
            if serr then
                print(serr)
            end
        end
    end
    z = {}
    startts = cts
end

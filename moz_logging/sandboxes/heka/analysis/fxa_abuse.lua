-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# FXA Account Creation Abuse Detection

Tracks the time between account creation request per IP address.

## Sample Configuration
```lua
filename = 'fxa_abuse.lua'
message_matcher = "Type == 'logging.fxa.auth_server.nginx.access' && Fields[request] =~ '^POST /v1/account/create'"
ticker_interval = 60
preserve_data = true

message_variable = "Fields[http_x_forwarded_for]"
-- max_items = 25000 -- maximum number of unique items to track

alert = {
  disabled = false,
  prefix = true,
  throttle = 5,
  modules = {
    email = {recipients = {"trink@mozilla.com"}},
  },
  thresholds = {
    min_count   = 200, -- minimun number of entries before triggering an alert (default 50)
    -- max_mean    = 1.0 -- maximum average amount of time, in seconds, between requests that is considered abusive
  }
}
```
--]]
require "math"
require "string"
local alert = require "heka.alert"

local message_variable  = read_config("message_variable") or error("must specify a 'message_variable'")
local max_items         = read_config("max_items") or 25000
local alert_min_count   = alert.get_threshold("min_count") or 50
local alert_max_mean    = alert.get_threshold("max_mean") or 1

local WEIGHT, TS, N, OM, NM, OS, NS = 1, 2, 3, 4, 5, 6, 7

local function running_stats(x, y)
    y[N] = y[N] + 1
    if y[N] == 1 then
        y[OM], y[NM] = x, x
        y[OS] = 0
    else
        y[NM] = y[OM] + (x - y[OM])/y[N]
        y[NS] = y[OS] + (x - y[OM])*(x - y[NM])
        y[OM] = y[NM]
        y[OS] = y[NS]
    end
end

items       = {}
items_size  = 0
active_day  = 0

function process_message ()
    local ts    = read_message("Timestamp")
    local item  = read_message(message_variable)
    if not item then return -1 end

    local day = math.floor(ts / (60 * 60 * 24 * 1e9))
    if day < active_day  then
        return 0 -- too old
    elseif day > active_day then
        active_day = day
        items = {}
        items_size = 0
    end

    local i = items[item]
    if i then
        if i[TS] ~= 0 then
             if not i[N] then i[N] = 0 end
             local x = ts - i[TS]
             running_stats(x/1e9, i)
        end
        i[TS] = ts
        i[WEIGHT] = i[WEIGHT] + 1
        return 0
    end

    if items_size == max_items then
        for k,v in pairs(items) do
            local weight = v[WEIGHT]
            if weight == 1 then
                items[k] = nil
                items_size = items_size - 1
            else
                v[WEIGHT] = weight - 1
            end
        end
    else
        i = {1, ts}
        items[item] = i
        items_size = items_size + 1
    end

    return 0
end

function timer_event(ns)
    add_to_payload(string.format("%s\tWeight\tCount\tMean\tSD\n", message_variable))
    for k, v in pairs(items) do
        if v[N] and v[N] >= alert_min_count then
            local variance = v[NS]/(v[N]-1)
            add_to_payload(string.format("%s\t%d\t%d\t%G\t%G\n", k, v[WEIGHT], v[N], v[NM], math.sqrt(variance)))
            if v[NM] <= alert_max_mean then
                alert.send(k, "abuse", string.format("Abuse detected %s: %s", message_variable, k))
            end
        end
    end
    inject_payload("tsv", "Statistics")
end

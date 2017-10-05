-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# FXA Active Daily Users

Tracks the total and Android active daily users over the last year.

## Sample Configuration
```lua
filename = 'fxa_active_daily_users.lua'
message_matcher = "Type == 'logging.fxa.auth_server.docker.fxa-auth|request.summary' && Fields[path] == '/v1/certificate/sign' && Fields[errno] == 0"
ticker_interval = 60
preserve_data = true
```
--]]
require "circular_buffer"
require "hyperloglog"
require "math"

local rows          = 365
local sec_per_row   = 60 * 60 * 24

active_day  = 0
td          = hyperloglog.new() -- total daily
ad          = hyperloglog.new() -- android daily
tdcb        = circular_buffer.new(rows, 1, sec_per_row)
adcb        = circular_buffer.new(rows, 1, sec_per_row)

local USERS         = 1
local NAME          = "users"
tdcb:set_header(USERS, NAME)
adcb:set_header(USERS, NAME)

local floor = math.floor

function process_message ()
    local ts = read_message("Timestamp")

    local day = floor(ts / (60 * 60 * 24 * 1e9))
    if day < active_day  then
        return 0 -- too old
    elseif day > active_day then
        active_day = day
        td:clear()
        ad:clear()
    end

    local uid = read_message("Fields[uid]")
    if type(uid) ~= "string" then return -1 end

    if td:add(uid) then
        tdcb:set(ts, USERS, td:count())
    end

    local user_agent_os = read_message("Fields[user_agent_os]")
    if user_agent_os and user_agent_os == "Android" then
        if ad:add(uid) then
            adcb:set(ts, USERS, ad:count())
        end
    end

    return 0
end

function timer_event(ns)
    inject_payload("cbuf", "Estimated Active Daily Users", tdcb)
    inject_payload("cbuf", "Estimated Active Daily Android Users", adcb)
end

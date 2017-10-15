-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# FXA Auth Memory

Tracks the FXA Auth memory statistics by process id.

## Sample Configuration
```lua
filename = 'fxa_auth_memory.lua'
message_matcher = "Type == 'logging.fxa.auth_server.docker.fxa-auth|stat' && Fields[stat] == 'mem'"
ticker_interval = 60
preserve_data = true

-- title = "Fxa Auth Server" -- report title
-- rows = 1440 -- number of rows in the graph data
-- sec_per_row = 60 -- number of seconds each row represents
-- pid_expiration = 600 -- number of seconds before an inactive process id expires
```
--]]
require "circular_buffer"
require "string"

local static_title      = read_config("title") or "Fxa Auth Server"
local rows              = read_config("rows") or 1440
local sec_per_row       = read_config("sec_per_row") or 60
local pid_expiration    = (read_config("pid_expiration") or 600) * 1e9
local HEAP_USED         = 1
local RSS               = 2

pids = {}
last_update = 0

function process_message ()
    local ts    = read_message("Timestamp")
    local host  = read_message("Hostname")
    local pid   = read_message("Pid")

    local key = string.format("%s PID:%d", host, pid)
    local p = pids[key]
    if not p then
        p  = circular_buffer.new(rows, 2, sec_per_row)
        p:set_header(HEAP_USED , "heapUsed" , "B", "max")
        p:set_header(RSS       , "rss"      , "B", "max")
        pids[key] = p
    end

    if last_update < ts then
        last_update = ts
    end

    local hu = read_message("Fields[heapUsed]")
    if type(hu) ~= "number" then return -1 end

    local rss = read_message("Fields[rss]")
    if type(rss) ~= "number" then return -1 end

    p:set(ts, HEAP_USED , hu)
    p:set(ts, RSS       , rss)
    return 0
end

function timer_event(ns)
    for k, v in pairs(pids) do
        if last_update - v:current_time() < pid_expiration then
            local title = string.format("%s:%s", static_title, k)
            inject_payload("cbuf", title, v)
        else
            pids[k] = nil
        end
    end
end

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# FXA Auth DB MySQL

Tracks the FXA Auth DB MySQL statistics by process id.

## Sample Configuration
```lua
filename = 'fxa_auth_mysql.lua'
message_matcher = "Type =~ '^logging%.fxa%.auth_server%.docker%.fxa%-auth%-db' && Fields[stat] == 'mysql'"
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
local CONNS             = 1
local QUEUE             = 2
local FREE              = 3
local ERRORS            = 4

pids = {}
last_update = 0

function process_message ()
    local ts    = read_message("Timestamp")
    local host  = read_message("Hostname")
    local pid   = read_message("Pid")

    local key = string.format("%s PID:%d", host, pid)
    local p = pids[key]
    if not p then
        p  = circular_buffer.new(rows, 4, sec_per_row)
        p:set_header(CONNS , "connections", "count", "max")
        p:set_header(QUEUE , "queue"      , "count", "max")
        p:set_header(FREE  , "free"       , "count", "max")
        p:set_header(ERRORS, "error"      , "count", "max")
        pids[key] = p
    end

    if last_update < ts then
        last_update = ts
    end

    local co = read_message("Fields[connections]")
    if type(co) ~= "number" then return -1 end

    local q = read_message("Fields[queue]")
    if type(q) ~= "number" then return -1 end

    local free = read_message("Fields[free]")
    if type(free) ~= "number" then return -1 end

    local err = read_message("Fields[errors]")
    if type(err) ~= "number" then return -1 end

    p:set(ts, CONNS , co)
    p:set(ts, QUEUE , q)
    p:set(ts, FREE  , free)
    p:set(ts, ERRORS, err)
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

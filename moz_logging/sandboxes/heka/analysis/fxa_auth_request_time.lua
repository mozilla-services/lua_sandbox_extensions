-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# FXA Auth Request Time

Tracks the FXA Auth average request time.

## Sample Configuration
```lua
filename = 'fxa_auth_request_time.lua'
message_matcher = "Type == 'logging.fxa.auth_server.docker.fxa-auth|request.summary' && Fields[errno] == 0 && (Fields[path] == '/v1/account/login' || Fields[path] == '/v1/account/create')"
ticker_interval = 60
preserve_data = true

-- rows = 1440 -- number of rows in the graph data
-- sec_per_row = 60 -- number of seconds each row represents
```
--]]
require "circular_buffer"
require "string"

local rows              = read_config("rows") or 1440
local sec_per_row       = read_config("sec_per_row") or 60
local COUNT             = 1
local TOTAL             = 2
local AVG               = 3

cbufs = {}

local function new_cbuf(path)
    local cb = circular_buffer.new(rows, 3, sec_per_row)
    cb:set_header(COUNT , "Count"   , "count")
    cb:set_header(TOTAL , "Total"   , "ms")
    cb:set_header(AVG   , "Avg"     , "ms", "none")
    cbufs[path] = cb
    return cb
end

function process_message ()
    local path = read_message("Fields[path]")
    if not path then return -1 end

    local cb = cbufs[path]
    if not cb then
        cb = new_cbuf(path)
        if not cb then return -1 end
    end

    local ts = read_message("Timestamp")
    local cnt = cb:add(ts, COUNT, 1)
    if not cnt then return 0 end

    local rt = read_message("Fields[t]")
    if type(rt) ~= "number" then return -1 end

    local total = cb:add(ts, TOTAL, rt)
    cb:set(ts, AVG, total/cnt)

    return 0
end

function timer_event(ns)
    for k,v in pairs(cbufs) do
        inject_payload("cbuf", k, v)
    end
end

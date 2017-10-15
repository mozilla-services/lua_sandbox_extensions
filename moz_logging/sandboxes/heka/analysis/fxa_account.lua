-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# FXA Account Login Failure Rate

Tracks the ratio login failures vs total attempts

## Sample Configuration
```lua
filename = 'fxa_account.lua'
message_matcher = "Type == 'logging.fxa.auth_server.docker.fxa-auth|request.summary' && Fields[path] == '/v1/account/login'"
ticker_interval = 60
preserve_data = true

-- rows = 1440 -- number of rows in the graph data
-- sec_per_row = 60 -- number of seconds each row represents
-- enable_delta = false -- enables/disables the cbufd output
```
--]]
require "circular_buffer"
require "string"

local title             = "Summary"
local rows              = read_config("rows") or 1440
local sec_per_row       = read_config("sec_per_row") or 60
local enable_delta      = read_config("enable_delta") or false

data = circular_buffer.new(rows, 3, sec_per_row)
local SUCCESS = data:set_header(1, "Success")
local FAILURE = data:set_header(2, "Failure")
local PFAIL   = data:set_header(3, "%Failure", "percent", "none")

function process_message ()
    local ts = read_message("Timestamp")
    local errno = read_message("Fields[errno]")
    if errno == 0 then
        local s = data:add(ts, SUCCESS, 1)
        if not s then return 0 end

        local f = data:get(ts, FAILURE)
        if f and f == f then
            local p = f / (f + s) * 100
            data:set(ts, PFAIL, p)
        else
            data:set(ts, PFAIL, 0)
        end
    else
        local f = data:add(ts, FAILURE, 1)
        if not f then return 0 end

        local s = data:get(ts, SUCCESS)
        if s and s == s then
            local p = f / (f + s) * 100
            data:set(ts, PFAIL, p)
        else
            data:set(ts, PFAIL, 100)
        end
    end
    return 0
end

function timer_event(ns)
    inject_payload("cbuf", title, data:format("cbuf"))
    if enable_delta then
        inject_payload("cbufd", title, data:format("cbufd"))
    end
end

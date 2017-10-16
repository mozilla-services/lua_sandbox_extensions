-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# FXA Auth Resend

Tracks the FXA Auth recovery email success/error count.

## Sample Configuration
```lua
filename = 'fxa_auth_resend.lua'
message_matcher = "Type == 'logging.fxa.auth_server.docker.fxa-auth|request.summary' && Fields[path] == '/v1/recovery_email/resend_code'"
ticker_interval = 60
preserve_data = true

-- rows = 1440 -- number of rows in the graph data
-- sec_per_row = 60 -- number of seconds each row represents
```
--]]
require "circular_buffer"
require "string"

local title             = "Summary"
local rows              = read_config("rows") or 1440
local sec_per_row       = read_config("sec_per_row") or 60

data = circular_buffer.new(rows, 2, sec_per_row)
local SUCCESS = data:set_header(1, "Success")
local FAILURE = data:set_header(2, "Failure")

function process_message ()
    local ts = read_message("Timestamp")
    local errno = read_message("Fields[errno]")
    if errno == 0 then
        data:add(ts, SUCCESS, 1)
    else
        data:add(ts, FAILURE, 1)
    end
    return 0
end

function timer_event(ns)
    inject_payload("cbuf", title, data:format("cbuf"))
end

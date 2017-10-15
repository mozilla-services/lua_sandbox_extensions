-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# FXA Auth Rate Limit

Tracks the FXA Auth rate limited requests.

## Sample Configuration
```lua
filename = 'fxa_auth_rate_limit.lua'
message_matcher = "Type == 'logging.fxa.auth_server.nginx.access' && Fields[status] == 429"
ticker_interval = 60
preserve_data = true

-- title = "HTTP Status" -- report title
-- rows = 1440 -- number of rows in the graph data
-- sec_per_row = 60 -- number of seconds each row represents
```
--]]
require "circular_buffer"
require "string"

local title             = "HTTP Status"
local rows              = read_config("rows") or 1440
local sec_per_row       = read_config("sec_per_row") or 60

status = circular_buffer.new(rows, 1, sec_per_row)
local HTTP_429 = status:set_header(1, "HTTP_429")

function process_message ()
    local ts = read_message("Timestamp")
    status:add(ts, HTTP_429, 1)
    return 0
end

function timer_event(ns)
    inject_payload("cbuf", title, status)
end

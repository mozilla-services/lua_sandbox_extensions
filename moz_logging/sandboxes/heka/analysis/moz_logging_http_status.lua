-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# HTTP Status

Graphs HTTP status codes using the numeric status code collected from
web server access logs.

## Sample Configuration
```lua
filename = 'moz_logging_http_status.lua'
message_matcher = "Type == 'logging.fxa.auth_server.nginx.access' && Fields[request] =~ '^POST /v1/account/create'"
ticker_interval = 60
preserve_data = true

-- rows = 60 * 60 * 24 * 8 + 1 -- number of rows in the graph data
-- sec_per_row = 60 -- number of seconds each row represents
-- status_field = "status" -- field containing the numeric HTTP status code

-- preservation_version (uint, optional, default 0)
-- If `preserve_data = true` then this value should be incremented every time
-- the `rows` or 'seconds_per_row' configuration is changed to prevent the
-- plugin from failing to start during data restoration.
```
--]]
_PRESERVATION_VERSION = read_config("preservation_version") or 0

require "circular_buffer"
require "string"

local rows              = read_config("rows") or 60 * 60 * 24 * 8 + 1
local sec_per_row       = read_config("sec_per_row") or 60
local status_field      = read_config("status_field") or "status"
status_field            = "Fields[" .. status_field .."]"

status = circular_buffer.new(rows, 6, sec_per_row)
status:set_header(1, "HTTP_100")
status:set_header(2, "HTTP_200")
status:set_header(3, "HTTP_300")
status:set_header(4, "HTTP_400")
status:set_header(5, "HTTP_500")
local HTTP_UNKNOWN = status:set_header(6, "HTTP_UNKNOWN")

function process_message ()
    local ts = read_message("Timestamp")
    local sc = read_message(status_field)
    if type(sc) ~= "number" then return -1 end

    local col = sc/100
    if col >= 1 and col < 6 then
        status:add(ts, col, 1) -- col will be truncated to an int
    else
        status:add(ts, HTTP_UNKNOWN, 1)
    end
    return 0
end

function timer_event(ns)
    inject_payload("cbuf", "HTTP Status", status)
end

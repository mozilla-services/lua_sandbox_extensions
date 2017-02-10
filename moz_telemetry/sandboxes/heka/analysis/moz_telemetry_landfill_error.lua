-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry Stream Error Aggregator

Simple debug tool to track the types of error in landfill processing. Used
when tuning the validation schemas.

## Sample Configuration
```lua
filename = "moz_telemetry_landfill_error.lua"
message_matcher = "Type == 'telemetry.error'"
ticker_interval = 60
```
--]]

require "string"

local err_msgs = {}

function process_message()
    local de = read_message("Fields[DecodeError]") or "<none>"
    local cnt = err_msgs[de]
    if cnt then
        err_msgs[de] = cnt + 1
    else
        err_msgs[de] = 1
    end
    return 0
end

function timer_event(ns, shutdown)
    for k,v in pairs(err_msgs) do
        add_to_payload(v, "\t", k, "\n")
    end
    inject_payload("tsv", "error")
end

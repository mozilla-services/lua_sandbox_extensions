-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# RST Heka Message Output

Writes a user friendly version (RST format) of the full Heka message to a file
or to stdout

## Sample Configuration
```lua
filename        = "heka_debug.lua"
message_matcher = "TRUE"
-- output_file     = "/tmp/out.log" -- if not set, sent to STDOUT
```
--]]

local open  = require "io".open
local concat = require "table".concat
local mi     = require "heka.msg_interpolate"

local fn = read_config("output_file")

local output = nil
if fn then
    output = assert(open(fn, 'a+'))
else
    output = require "io".output()
end

function process_message()
    local raw = read_message("raw")
    local msg = decode_message(raw)
    output:write(":Uuid: ", mi.get_uuid(msg.Uuid), "\n")
    output:write(":Timestamp: ", mi.get_timestamp(msg.Timestamp), "\n")
    output:write(":Type: ", msg.Type or "<nil>", "\n")
    output:write(":Logger: ", msg.Logger or "<nil>", "\n")
    output:write(":Severity: ", msg.Severity or 7, "\n")
    output:write(":Payload: ", msg.Payload or "<nil>", "\n")
    output:write(":EnvVersion: ", msg.EnvVersion or "<nil>", "\n")
    output:write(":Pid: ", msg.Pid or "<nil>", "\n")
    output:write(":Hostname: ", msg.Hostname or "<nil>", "\n")
    output:write(":Fields:\n")
    for i, v in ipairs(msg.Fields or {}) do
        output:write("    | name: ", v.name,
              " type: ", v.value_type or 0,
              " representation: ", v.representation or "<nil>",
              " value: ")
        if v.value_type == 4 then
            for j, w in ipairs(v.value) do
                if j ~= 1 then output:write(",") end
                if w then output:write("true") else output:write("false") end
            end
            output:write("\n")
        else
            output:write(concat(v.value, ","), "\n")
        end
    end
    output:write("\n")
    output:flush()
    return 0
end

function timer_event(ns)
    -- no op
end

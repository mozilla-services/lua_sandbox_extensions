-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Framed Protobuf Message Decoder Module

This decoder is for when multiple Heka messages are sent in one payload
(e.g. Kinesis packing), it will not handle a message split across payloads.

## Decoder Configuration Table
* none

## Functions

### decode

Decode and inject the resulting message(s)

*Arguments*
- data (string) - Framed Protobuf message(s) with a Heka schema

*Return*
- nil - throws an error on an invalid data type, inject_message failure etc.

--]]

-- Imports
local module_name       = ...
local hsr               = create_stream_reader(module_name)
local inject_message    = inject_message

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

function decode(data)
    local found, bytes, read
    repeat
        repeat
            found, bytes, read = hsr:find_message(data)
            if found then inject_message(hsr) end
        until not found
    until read == 0
end

return M

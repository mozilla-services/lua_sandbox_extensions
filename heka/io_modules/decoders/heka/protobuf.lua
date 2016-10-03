-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Protobuf Message Decoder Module

## Decoder Configuration Table
* none

## Functions

### decode

Decode and inject the resulting message

*Arguments*
- data (string) - Protobuf message with a Heka schema

*Return*
- nil - throws an error on an invalid data type, inject_message failure etc.

--]]

-- Imports
local inject_message = inject_message

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

function decode(data)
    inject_message(data)
end

return M

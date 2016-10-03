-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Framed Protobuf Message Encoder Module

## Encoder Configuration Table
* none

## Functions

### encode

Returns the read_message userdata reference to retrieve the framed Heka protobuf
message.

*Arguments*
- none

*Return*
- data (userdata) - reference to the framed message

--]]

-- Imports
local framed = read_message("framed", nil, nil, true)

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

function encode()
    return framed
end

return M

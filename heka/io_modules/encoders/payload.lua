-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Payload Encoder Module
Extracts the payload from the provided Heka message and converts it into a byte
stream for delivery to an external resource.

## Encoder Configuration Table
* none

## Functions

### encode

Returns the read_message reference to retrieve the payload from the Heka
message.

*Arguments*
- none

*Return*
- data (userdata) - reference to the message Payload

--]]

-- Imports

local payload = read_message("Payload", nil, nil, true)

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

function encode()
    return payload
end

return M

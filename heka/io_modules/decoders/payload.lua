-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Payload Decoder Module
Takes the raw data, which should be a UTF-8 string, and adds it to the Heka
message Payload header.

## Decoder Configuration Table
- none

## Functions

### decode

Decode and inject the resulting message

*Arguments*
- data (string) - Data to write to the msg.Payload
- default_headers (table, nil/none) - Heka message table containing the default
  header values to use, if not populated by the decoder. Default 'Fields' cannot
  be provided.

*Return*
- nil - throws an error on inject_message failure.

--]]

-- Imports
local inject_message = inject_message

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local msg = { }

function decode(data, dh)
    if dh then
        msg.Uuid        = dh.Uuid
        msg.Logger      = dh.Logger
        msg.Hostname    = dh.Hostname
        msg.Timestamp   = dh.Timestamp
        msg.Type        = dh.Type
        -- msg.Payload     = dh.Payload -- always overwritten
        msg.EnvVersion  = dh.EnvVersion
        msg.Pid         = dh.Pid
        msg.Severity    = dh.Severity
    end
    msg.Payload = data
    inject_message(msg)
end

return M

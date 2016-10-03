-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka JSON Message Decoder Module
https://mana.mozilla.org/wiki/display/CLOUDSERVICES/Logging+Standard

The above link isn't publicly accessible but it basically describes the Heka
message format with a JSON schema. The JSON will be decoded and passed directly
to inject_message so it needs to decode into a Heka message table described
here: https://mozilla-services.github.io/lua_sandbox/heka/message.html

## Decoder Configuration Table
* none

## Functions

### decode

Decode and inject the resulting message

*Arguments*
- data (string) - JSON message with a Heka schema
- default_headers (table, nil/none) - Heka message table containing the default
  header values to use, if not populated by the decoder. Default 'Fields' cannot
  be provided.

*Return*
- nil - throws an error on an invalid data type, JSON parse error,
  inject_message failure etc.

--]]

-- Imports
local cjson             = require "cjson"
local inject_message    = inject_message

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

function decode(data, dh)
    local msg = cjson.decode(data)

    if dh then
        if not msg.Uuid then msg.Uuid = dh.Uuid end
        if not msg.Logger then msg.Logger = dh.Logger end
        if not msg.Hostname then msg.Hostname = dh.Hostname end
        -- if not msg.Timestamp then msg.Timestamp = dh.Timestamp end -- always overwritten
        if not msg.Type then msg.Type = dh.Type end
        if not msg.Payload then msg.Payload = dh.Payload end
        if not msg.EnvVersion then msg.EnvVersion = dh.EnvVersion end
        if not msg.Pid then msg.Pid = dh.Pid end
        if not msg.Severity then msg.Severity = dh.Severity end
    end

    inject_message(msg)
end

return M

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

```lua
decoders_heka_json = {
  -- Preserve the default_headers passed to decode by storing the json message
  -- in Fields, after flattening the json message with a delimiter.
  preserve_metadata = false, -- default

  -- Use the Timestamp from json when preserve_metadata is true.
  preserve_metadata_use_timestamp = false, -- default

  -- Delimiter to use when flattening the Fields object of a json message.
  -- Used only when preserve_metadata is true.
  flatten_delimiter = ".", -- default
}
```

## Functions

### decode

Decode and inject the resulting message

*Arguments*
- data (string) - JSON message with a Heka schema
- default_headers (optional table) - Heka message table containing the default
  header values to use, if they are not populated by the decoder. If 'Fields'
  is specified it should be in the hashed based format see:
  http://mozilla-services.github.io/lua_sandbox/heka/message.html

*Return*
- nil - throws an error on an invalid data type, JSON parse error,
  inject_message failure etc.

--]]

-- Imports
local module_name   = ...
local module_cfg    = require "string".gsub(module_name, "%.", "_")
local cjson = require "cjson"

local pairs = pairs
local type  = type

local inject_message = inject_message

local cfg = read_config(module_cfg) or {}
assert(type(cfg) == "table", module_cfg .. " must be a table")
cfg.flatten_delimiter = cfg.flatten_delimiter or "."
assert(type(cfg.flatten_delimiter) == "string", module_cfg .. ".flatten_delimiter must be a string")
fields_prefix = "Fields" .. cfg.flatten_delimiter

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

function decode(data, dh)
    local msg = cjson.decode(data)
    if cfg.preserve_metadata then
        if type(msg.Fields) == "table" then
            for k,v in pairs(msg.Fields) do
                msg[fields_prefix..k] = v
            end
            msg.Fields = nil
        end
        msg = {Fields=msg}
        if cfg.preserve_metadata_use_timestamp then
            msg.Timestamp = msg.Fields.Timestamp
        end
    end

    if dh then
        if not msg.Uuid then msg.Uuid = dh.Uuid end
        if not msg.Logger then msg.Logger = dh.Logger end
        if not msg.Hostname then msg.Hostname = dh.Hostname end
        if not msg.Timestamp then msg.Timestamp = dh.Timestamp end
        if not msg.Type then msg.Type = dh.Type end
        if not msg.Payload then msg.Payload = dh.Payload end
        if not msg.EnvVersion then msg.EnvVersion = dh.EnvVersion end
        if not msg.Pid then msg.Pid = dh.Pid end
        if not msg.Severity then msg.Severity = dh.Severity end

        if type(dh.Fields) == "table" then
            if not msg.Fields then msg.Fields = {} end
            for k,v in pairs(dh.Fields) do
                if msg.Fields[k] == nil then
                    msg.Fields[k] = v
                end
            end
        end
    end

    inject_message(msg)
end

return M

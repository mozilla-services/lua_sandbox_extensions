-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka JSON Message Decoder Module with Mutate capabilities
https://wiki.mozilla.org/Firefox/Services/Logging

## Decoder Configuration Table

```lua
decoders_heka_json_mutate = {
  -- Preserve the default_headers passed to decode by storing the json message
  -- in Fields, after flattening the json message with a delimiter.
  preserve_metadata = false, -- default

  -- Use the Timestamp from json when preserve_metadata is true.
  preserve_metadata_use_timestamp = false, -- default

  -- Delimiter to use when flattening the Fields object of the json message.
  -- Used only when preserve_metadata is true.
  flatten_delimiter = ".", -- default

  -- Remove these fields from the json message
  scrub_fields = {}, -- default

  -- For key, value in user_agent_transforms
  -- transform Fields[key] into Fields[value.."browser"], Fields[value.."version"], Fields[value.."os"].
  user_agent_transforms = {agent = "user_agent_"}, -- default {}

  -- Always preserve the original fields if user_agent_transforms occur.
  user_agent_keep = false, -- default

  -- Only preserve the original fields if user_agent_transforms occur and fail.
  user_agent_conditional = false, -- default
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
local module_name    = ...
local module_cfg     = require "string".gsub(module_name, "%.", "_")
local cjson          = require "cjson"
local inject_message = inject_message
local ipairs         = ipairs
local pairs          = pairs
local type           = type

local cfg = read_config(module_cfg) or {}
assert(type(cfg) == "table", module_cfg .. " must be a table")
cfg.scrub_fields = cfg.scrub_fields or {}
cfg.user_agent_transforms = cfg.user_agent_transforms or {}
cfg.flatten_delimiter = cfg.flatten_delimiter or "."
assert(type(cfg.flatten_delimiter) == "string", module_cfg .. ".flatten_delimiter must be a string")
local fields_prefix = "Fields" .. cfg.flatten_delimiter

local clf
if cfg.user_agent_transform then
    clf = require "lpeg.common_log_format"
end

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

function decode(data, dh)
    local msg = cjson.decode(data)

    -- transform user agent fields
    for field, prefix in pairs(cfg.user_agent_transforms) do
        if msg.Fields[field] then
            msg.Fields[prefix.."browser"],
            msg.Fields[prefix.."version"],
            msg.Fields[prefix.."os"] = clf.normalize_user_agent(msg[field])
            if not ((cfg.user_agent_conditional and not msg.Fields[prefix.."browser"]) or cfg.user_agent_keep) then
                msg.Fields[field] = nil
            end
        end
    end

    -- scrub fields
    for _, field in ipairs(cfg.scrub_fields) do
        msg.Fields[field] = nil
    end

    -- preserve metadata
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

    -- apply default headers
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

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Transforms a generic lua table into the Heka message schema.

The configuration allows a grammar or a function to be specified for the initial
parse and a map configuration allows the resulting table to be transformed;
variables renamed, moved, and cast to their desired types.

## Decoder Configuration Table

```lua
decoders_table_to_message = {
    module_name     = "lpeg.logfmt"
    module_grammar  = "grammar" -- or -- module_function = "decode"

    map = { -- optional if not provided a default mapping will be used
        -- see https://mozilla-services.github.io/lua_sandbox_extensions/heka/modules/heka/util.html#table_to_message
        time = {header = "Timestamp"},
        len  = {field = "length", type = "int", representation = "inches"}
    }
}
```

## Functions

### decode

Decode and inject the resulting message

*Arguments*
- data (string) - input data to be parsed
- default_headers (optional table) - Heka message table containing the default
  header values to use, if they are not populated by the decoder. If 'Fields'
  is specified it should be in the hashed based format see:
  http://mozilla-services.github.io/lua_sandbox/heka/message.html

*Return*
- nil - throws an error on an invalid data type, parse error,
  inject_message failure etc.

--]]

-- Imports
local module_name    = ...
local module_cfg     = require "string".gsub(module_name, "%.", "_")
local util           = require "heka.util"
local inject_message = inject_message
local pairs          = pairs
local type           = type

local cfg = read_config(module_cfg) or {}
assert(type(cfg) == "table", module_cfg .. " must be a table")
assert(cfg.map == nil or type(cfg.map) == "table", "cfg.map must be nil or a table")

local pmod = require(cfg.module_name)
local fn
if cfg.module_grammar then
    require "lpeg"
    fn = function (data) return lpeg.match(pmod[cfg.module_grammar], data) end
else
    fn = pmod[cfg.module_function]
end


local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

function decode(data, dh)
    local msg = fn(data)
    if not msg then return "parse failed" end

    msg = util.table_to_message(msg, cfg.map)
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

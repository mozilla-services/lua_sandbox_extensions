-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Transforms a generic lua table into fields in the Heka message schema

The configuration allows a grammar or a function to be specified for the initial
parse.

This decoder makes use of util.table_to_fields. If the resulting table after
grammar/module_function is applied contains nested tables, these tables
are flattened by combining the key name with parent keys. The resulting flattened
table is then used as message Fields with the default headers.

## Decoder Configuration Table

```lua
decoders_table_to_fields = {
    module_name     = "cjson"
    module_function = "decode" -- or module_grammar to use a grammar
    -- max_depth = 5 -- optional, maximum depth for nested table conversion (default no limit)
    -- separator = "." -- optional, override default nested table key seperator in util.table_to_fields
}
```

## Functions

### decode

Decode and inject the resulting message

*Arguments*
- data (string) - input data to be parsed into fields
- default_headers (optional table) - Heka message table containing the default
  header values to use, if they are not populated by the decoder. If 'Fields'
  is specified it should be in the hashed based format see:
  http://mozilla-services.github.io/lua_sandbox/heka/message.html

*Return*
- nil - throws an error on an invalid data type, parse error,
  inject_message failure etc.
--]]

local module_name    = ...
local module_cfg     = require "string".gsub(module_name, "%.", "_")
local util           = require "heka.util"
local inject_message = inject_message
local pairs          = pairs
local type           = type

local cfg = read_config(module_cfg) or {}
assert(type(cfg) == "table", module_cfg .. " must be a table")
local max_depth = nil
local sep = nil
if type(cfg.max_depth) == "number" then max_depth = cfg.max_depth end
if type(cfg.separator) == "string" then sep = cfg.separator end

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
    local t = fn(data)
    if not t then return "parse failed" end

    local f = {}
    util.table_to_fields(t, f, nil, sep, max_depth)
    msg = { Fields = f }

    -- apply default headers
    if dh then
        msg.Uuid = dh.Uuid
        msg.Logger = dh.Logger
        msg.Hostname = dh.Hostname
        msg.Timestamp = dh.Timestamp
        msg.Type = dh.Type
        msg.Payload = dh.Payload
        msg.EnvVersion = dh.EnvVersion
        msg.Pid = dh.Pid
        msg.Severity = dh.Severity

        if type(dh.Fields) == "table" then
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

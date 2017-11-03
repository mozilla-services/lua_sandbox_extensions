-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Line Splitter Message Decoder Module

Converts a single message packed with individual new line delimited messages
into multiple messages.

## Decoder Configuration Table

```lua
decoders_line_splitter = {
  sub_decoder = Decoder module name or grammar module name
}
```

## Functions

### decode

Decode and inject the resulting message

*Arguments*
- data (string) - JSON messages, one per line, with a Heka schema
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
local cfg = read_config(module_cfg) or {}
assert(type(cfg.sub_decoder) == "string", "sub_decoder must be set")

local string    = require "string"
local sd_module = require(cfg.sub_decoder)

local assert = assert
local pairs  = pairs
local pcall  = pcall
local type   = type

local inject_message = inject_message
local read_config    = read_config

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local msg = {}

local sub_decoder
if cfg.sub_decoder:match("^decoders%.") then
    sub_decoder = sd_module.decode
    assert(type(sub_decoder) == "function", "sub_decoders, no decode function defined")
else
    local grammar = sd_module.grammar or sd_module.syslog_grammar
    assert(type(grammar) == "userdata", "sub_decoders, no grammar defined")
    sub_decoder = function(data, dh)
        msg.Fields = grammar:match(data)
        if not msg.Fields then return "parse failed" end
        if dh then
            msg.Uuid        = dh.Uuid
            msg.Logger      = dh.Logger
            msg.Hostname    = dh.Hostname
            msg.Timestamp   = dh.Timestamp
            msg.Type        = dh.Type
            msg.Payload     = dh.Payload
            msg.EnvVersion  = dh.EnvVersion
            msg.Pid         = dh.Pid
            msg.Severity    = dh.Severity
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
end

local err_msg = {
    Logger  = read_config("Logger"),
    Type    = "error",
    Payload = nil,
    Fields  = {
        data = nil
    }
}

function decode(data, dh)
     for line in string.gmatch(data, "([^\n]+)\n*") do
         local err = sub_decoder(line, dh)
         if err then
             err_msg.Payload = err
             err_msg.Fields.data = line
             pcall(inject_message, err_msg)
         end
     end
end

return M

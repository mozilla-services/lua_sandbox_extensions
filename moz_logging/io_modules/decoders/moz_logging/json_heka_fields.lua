-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka JSON Message Fields Decoder Module
https://wiki.mozilla.org/Firefox/Services/Logging

The above link describes the Heka message format with a JSON schema. The JSON
will be decoded and passed as the msg.Fields table see:
https://mozilla-services.github.io/lua_sandbox/heka/message.html

## Decoder Configuration Table
* none

## Functions

### decode

Decode and inject the resulting message

*Arguments*
- data (string) - JSON message with a Heka message Fields schema
- default_headers (optional table) - Heka message table containing the default
  header values to use, if they are not populated by the decoder. If 'Fields'
  is specified it should be in the hashed based format see:
  http://mozilla-services.github.io/lua_sandbox/heka/message.html

*Return*
- nil - throws an error on an invalid data type, JSON parse error,
  inject_message failure etc.

--]]

-- Imports
local cjson  = require "cjson"
local string = require "string"

local pcall = pcall
local type  = type
local inject_message = inject_message
local logger = read_config("Logger")

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local err_msg = {
    Logger  = logger,
    Type    = "error",
    Payload = nil,
    Fields  = {
        data = nil
    }
}

function decode(data, dh)
    for line in string.gmatch(data, "([^\n]+)\n*") do
        local ok, msg = pcall(cjson.decode, line)
        if ok then
            msg = {Fields = msg}
            if dh then
                msg.Uuid       = dh.Uuid
                msg.Logger     = dh.Logger
                msg.Hostname   = dh.Hostname
                msg.Timestamp  = dh.Timestamp
                msg.Type       = dh.Type
                msg.Payload    = dh.Payload
                msg.EnvVersion = dh.EnvVersion
                msg.Pid        = dh.Pid
                msg.Severity   = dh.Severity
                if type(dh.Fields) == "table" then
                    for k,v in pairs(dh.Fields) do
                        if msg.Fields[k] == nil then
                            msg.Fields[k] = v
                        end
                    end
                end
            end
            ok, msg = pcall(inject_message, msg)
            if not ok then
                err_msg.Payload = msg
                err_msg.Fields.data = line
                pcall(inject_message, err_msg)
            end
        end -- Bug 1405816 if it is not JSON silently ignore it
    end
end

return M

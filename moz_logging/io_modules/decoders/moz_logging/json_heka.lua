-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Multi-line Heka JSON Message Decoder Module
https://wiki.mozilla.org/Firefox/Services/Logging

The above link describes the Heka message format with a JSON schema. The JSON
will be decoded and passed directly to inject_message so it needs to decode into
a Heka message table described here:
https://mozilla-services.github.io/lua_sandbox/heka/message.html

## Decoder Configuration Table
* none

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
local clf    = require "lpeg.common_log_format"
local cjson  = require "cjson"
local string = require "string"
local util   = require "heka.util"

local pcall  = pcall

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
             if msg.Logger then
                 msg.Logger = string.format("%s|%s", logger, msg.Logger)
             else -- unknown JSON, flatten to fields
                 local fields = {}
                 util.table_to_fields(msg, fields, nil, ".", 4)
                 msg = {Fields = fields}
             end
             if dh and dh.Type then
                 if msg.Type then
                     msg.Type = string.format("%s|%s", dh.Type, msg.Type)
                 else
                     msg.Type = dh.Type
                 end
             end

             if msg.Fields then
                 local agent = msg.Fields.agent
                 if agent then
                     msg.Fields.user_agent_browser,
                     msg.Fields.user_agent_version,
                     msg.Fields.user_agent_os = clf.normalize_user_agent(agent)
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

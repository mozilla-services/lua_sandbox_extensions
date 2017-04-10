-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Gelf Decoder Module
Takes a gelf message, which should be a UTF-8 string, and adds it to the Heka
message Payload header.

## Decoder Configuration Table
- none

## Functions

### decode

Decode and inject the resulting message

*Arguments*
- data (string) - Data to write to the msg.Payload
- default_headers (optional table) - Heka message table containing the default
  header values to use, if they are not populated by the decoder. If 'Fields'
  is specified it should be in the hashed based format see:
  http://mozilla-services.github.io/lua_sandbox/heka/message.html

*Return*
- nil - throws an error on inject_message failure.

--]]

-- Imports

local module_name    = ...
local module_cfg     = require "string".gsub(module_name, "%.", "_")
local cjson          = require "cjson"
local inject_message = inject_message
local ipairs         = ipairs
local pairs          = pairs
local type           = type
local table          = require "table"
local string         = require "string"
local io = require "io"
local read_config    = read_config

local cfg = read_config(module_cfg) or {}


local map = {}
local function table_length(t)
   local c = 0
   for k,v in pairs(t) do
      c = c+1
   end
   return c
end

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local function build_and_send_message(data, dh)
   local msg_type = read_config("type")
   local json = cjson.decode(data)
   local msg = {
      Timestamp  = nil,
      EnvVersion = nil,
      Hostname   = nil,
      Type       = msg_type,
      Payload    = nil,
      Fields     = nil,
      Severity   = nil
   }
   if dh then
      if not msg.Uuid then msg.Uuid = dh.Uuid end
      if not msg.Logger then msg.Logger = dh.Logger end
      if not msg.Hostname then msg.Hostname = dh.Hostname end
      if not msg.Timestamp then msg.Timestamp = dh.Timestamp end
      if not msg.Type then msg.Type = dh.Type end
      if not msg.Payload then msg.Payload = data end
      if not msg.EnvVersion then msg.EnvVersion = dh.EnvVersion end
      if not msg.Pid then msg.Pid = dh.Pid end
      if not msg.Severity then msg.Severity = dh.Severity end
   end
   if type(json["timestamp"]) ~= "number" then return -1, "Message does not follow gelf syntax" end
   msg.Timestamp = json["timestamp"] * 1e9
   msg.EnvVersion = json["version"]
   msg.Severity = json["level"]
   msg.Hostname = json["host"]
   msg.Fields = json
   json["timestamp"] = nil
   json["version"] = nil
   json["level"] = nil
   json["host"] = nil
   inject_message(msg)
   return nil
end

function decode(data, dh)
   if string.byte(data:sub(1,1)) == 0x1e and string.byte(data:sub(2,2)) == 0x0f then
      message_id = data:sub(3, 10)
      sequence_number = string.byte(data:sub(11, 11))
      sequence_count = string.byte(data:sub(12, 12))
      if map[message_id] == nil then
         map[message_id] = {}
      end
      map[message_id][sequence_number + 1] = data:sub(13)
      if table_length(map[message_id]) == sequence_count then
         local str = ""
         for k,v in pairs(map[message_id]) do
            str = str .. v
         end
         map[message_id] = nil
         return build_and_send_message(str, dh)
      end
   else
      return build_and_send_message(data, dh)
   end
   return nil
end

return M

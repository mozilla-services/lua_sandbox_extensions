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
  -- printf_messages (table/nil) see: https://mozilla-services.github.io/lua_sandbox_extensions/lpeg/modules/lpeg/printf.html
  -- sub_decoder (string/table) see: https://mozilla-services.github.io/lua_sandbox_extensions/lpeg/io_modules/lpeg/sub_decoder_util.html
}
```

## Functions

### decode

Decode and inject the resulting message

*Arguments*
- data (string) - Raw data from the input sandbox that needs
  parsing/decoding/transforming
- default_headers (table/nil/none) - Heka message table containing the default
  header values to use, if they are not populated by the decoder. If 'Fields'
  is specified it should be in the hashed based format see:
  http://mozilla-services.github.io/lua_sandbox/heka/message.html. In the case
  of multiple decoders this may be the message from the previous input/decoding
  step.
- mutable (bool/nil/none) - Flag indicating if the decoder can modify the
  default_headers/msg structure in place or if it has to be copied first.

*Return*
- err (nil, string) or throws an error on invalid data or an inject message
  failure
    - nil - if the decode was successful
    - string - error message if the decode failed (e.g. no match)

--]]

-- Imports
local module_name   = ...
local module_cfg    = require "string".gsub(module_name, "%.", "_")
local cfg = read_config(module_cfg) or {}

local sdu           = require "lpeg.sub_decoder_util"
local sub_decoder   = sdu.load_sub_decoder(cfg.sub_decoder, cfg.printf_messages)

local string = string
local assert = assert
local pairs  = pairs
local pcall  = pcall
local type   = type

local inject_message = inject_message
local read_config    = read_config

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module


local err_msg = {
    Type    = "error.decode",
    Payload = nil,
    Fields  = {
        data = nil
    }
}


function decode(data, dh, mutable)
     for line in string.gmatch(data, "([^\n]+)\n*") do
         local err = sub_decoder(line, msg, mutable)
         if err then
             err_msg.Payload = err
             err_msg.Fields.data = line
             pcall(inject_message, err_msg)
         end
     end
end

return M

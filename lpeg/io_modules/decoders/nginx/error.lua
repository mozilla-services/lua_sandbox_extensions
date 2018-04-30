-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Nginx Error Log Decoder Module (DEPRECATED)

We are moving to a configuration based setup to allow for more flexible
transformations. The following will produce the equivalent behavior.
```lua

decoder_module  = {
  {
    {"lpeg.common_log_format#nginx_error_grammar"},
    {
      time      = "lpeg.heka#set_timestamp",
      msg       = "lpeg.heka#set_payload",
      severity  = "lpeg.heka#set_severity",
      pid       = "lpeg.heka#set_pid"
    }
  }
}
```

## Decoder Configuration Table
- none

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
local sdu       = require "lpeg.sub_decoder_util"
local grammar   = require "lpeg.common_log_format".nginx_error_grammar

local inject_message = inject_message

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

function decode(data, dh, mutable)
    local fields = grammar:match(data)
    if not fields then return "parse failed" end

    local msg = sdu.copy_message(dh, mutable)
    msg.Timestamp = fields.time
    msg.Payload   = fields.msg
    msg.Severity  = fields.severity
    msg.Pid       = fields.pid
    fields.time     = nil
    fields.msg      = nil
    fields.severity = nil
    fields.pid      = nil
    sdu.add_fields(msg, fields)
    inject_message(msg)
end

return M

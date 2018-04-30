-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Nginx Access Log Decoder Module (DEPRECATED)

We are moving to a configuration based setup to allow for more flexible
transformations. The following will produce the equivalent default behavior.
```lua
log_format = '$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent"'

decoder_module  = {
  {
    {"lpeg.common_log_format#build_nginx_grammar", log_format},
    {
      time = "lpeg.heka#set_timestamp",
      Payload = "lpeg.heka#remove_payload",
      --http_user_agent = "lpeg.heka#add_normalized_user_agent",
    }
  }
}

lpeg_heka = {
    user_agent_normalized_field_name = "user_agent", -- set to override the original field name prefix
    user_agent_remove = true, -- remove the user agent field after a successful normalization
}
```

## Decoder Configuration Table (required)

```lua
decoders_nginx_access = {
  -- The ‘log_format’ configuration directive from the nginx.conf.
  -- The $time_local or $time_iso8601 variable is converted to the number of
  -- nanosecond  since the Unix epoch and used to set the Timestamp on the message.
  -- http://nginx.org/en/docs/http/ngx_http_log_module.html
  log_format = '$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent"',

  -- Transform the http_user_agent into user_agent_browser, user_agent_version, user_agent_os.
  user_agent_transform = false, -- default

  -- Always preserve the http_user_agent value if transform is enabled.
  user_agent_keep = false, -- default

  -- Only preserve the http_user_agent value if transform is enabled and fails.
  user_agent_conditional = false, -- default

  -- Always preserve the original log line in the message payload.
  payload_keep = false, -- default
}
```

## Functions

### decode

Decode and inject the resulting message

*Arguments*
- data (string) - Nginx access log line
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
local sdu           = require "lpeg.sub_decoder_util"
local clf           = require "lpeg.common_log_format"

local inject_message = inject_message

local cfg = read_config(module_cfg)
assert(type(cfg) == "table", module_cfg .. " must be a table")
local grammar = clf.build_nginx_grammar(cfg.log_format)

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module


function decode(data, dh, mutable)
    local fields = grammar:match(data)
    if not fields then return "parse failed" end

    local msg = sdu.copy_message(dh, mutable)
    if cfg.payload_keep then msg.Payload = data end

    if fields.http_user_agent and cfg.user_agent_transform then
        fields.user_agent_browser,
        fields.user_agent_version,
        fields.user_agent_os = clf.normalize_user_agent(fields.http_user_agent)
        if not ((cfg.user_agent_conditional and not fields.user_agent_browser) or cfg.user_agent_keep) then
            fields.http_user_agent = nil
        end
    end

    msg.Timestamp = fields.time
    fields.time = nil
    sdu.add_fields(msg, fields)
    inject_message(msg)
end

return M

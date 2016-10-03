-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Nginx Access Log Decoder Module

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
- default_headers (table, nil/none) - Heka message table containing the default
  header values to use, if not populated by the decoder. Default 'Fields' cannot
  be provided.

*Return*
- err (nil, string)
    - nil if the data was successfully parsed/decoded and injected
    - string error message if the decoding failed
    - throws an error on an invalid data type, inject_message failure etc.

--]]

-- Imports
local module_name       = ...
local module_cfg        = require "string".gsub(module_name, "%.", "_")

local clf               = require "lpeg.common_log_format"
local inject_message    = inject_message

local cfg = read_config(module_cfg)
assert(type(cfg) == "table", module_cfg .. " must be a table")
local grammar = clf.build_nginx_grammar(cfg.log_format)

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local msg = { }

function decode(data, default_headers)
    local fields = grammar:match(data)
    if not fields then return "parse failed" end

    if default_headers then
        msg.Uuid        = default_headers.Uuid
        msg.Logger      = default_headers.Logger
        msg.Hostname    = default_headers.Hostname
        -- msg.Timestamp   = default_headers.Timestamp -- always overwritten
        msg.Type        = default_headers.Type
        msg.Payload     = default_headers.Payload
        msg.EnvVersion  = default_headers.EnvVersion
        msg.Pid         = default_headers.Pid
        msg.Severity    = default_headers.Severity
    end

    msg.Timestamp = fields.time
    fields.time = nil

    if cfg.payload_keep then msg.Payload = data end

    if fields.http_user_agent and cfg.user_agent_transform then
        fields.user_agent_browser,
        fields.user_agent_version,
        fields.user_agent_os = clf.normalize_user_agent(fields.http_user_agent)
        if not ((cfg.user_agent_conditional and not fields.user_agent_browser) or cfg.user_agent_keep) then
            fields.http_user_agent = nil
        end
    end

    msg.Fields = fields
    inject_message(msg)
end

return M

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Syslog Decoder Module

## Decoder Configuration Table
```lua
decoders_syslog = {
  -- template (string) - The 'template' configuration string from rsyslog.conf
  -- see http://rsyslog-5-8-6-doc.neocities.org/rsyslog_conf_templates.html
  -- Default:
  -- template = "<%PRI%>%TIMESTAMP% %HOSTNAME% %syslogtag:1:32%%msg:::sp-if-no-1st-sp%%msg%", -- RSYSLOG_TraditionalForwardFormat

  -- printf_messages = nil, -- see: https://mozilla-services.github.io/lua_sandbox_extensions/lpeg/modules/lpeg/
  -- sub_decoders = nil, -- see: https://mozilla-services.github.io/lua_sandbox_extensions/lpeg/io_modules/lpeg/sub_decoder_util.html
}
```

## Functions

### decode

Decode and inject the resulting message

*Arguments*
- data (string) - syslog message
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
local string        = string
local syslog        = require "lpeg.syslog"
local sdu           = require "lpeg.sub_decoder_util"

local cfg = read_config(module_cfg) or {}
assert(type(cfg) == "table", module_cfg .. " must be a table")
local template      = cfg.template or "<%PRI%>%TIMESTAMP% %HOSTNAME% %syslogtag:1:32%%msg:::sp-if-no-1st-sp%%msg%"
local grammar       = syslog.build_rsyslog_grammar(template)
local sub_decoders  = sdu.load_sub_decoders(cfg.sub_decoders, cfg.printf_messages)

local pairs = pairs
local type  = type

local inject_message = inject_message

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

function decode(data, dh, mutable)
    local fields = grammar:match(data)
    if not fields then return module_name .. " parse failed" end
    local programname = ""

    local msg = sdu.copy_message(dh, mutable)
    if fields.pri then
        msg.Severity = fields.pri.severity
        fields.syslogfacility = fields.pri.facility
        fields.pri = nil
    else
        msg.Severity = fields.syslogseverity or fields["syslogseverity-text"]
        or fields.syslogpriority or fields["syslogpriority-text"]

        fields.syslogseverity = nil
        fields["syslogseverity-text"] = nil
        fields.syslogpriority = nil
        fields["syslogpriority-text"] = nil
    end

    if fields.syslogtag then
        programname = fields.syslogtag.programname
        fields.programname = programname
        msg.Pid = fields.syslogtag.pid
        fields.syslogtag = nil
    end

    msg.Timestamp = fields.timestamp
    fields.timestamp = nil

    msg.Hostname = fields.hostname or fields.source
    fields.hostname = nil
    fields.source = nil

    local payload = fields.msg
    fields.msg = nil
    sdu.add_fields(msg, fields)

    local df = sub_decoders[programname]
    if df then
        local err = df(payload, msg, true)
        if err then
            err = string.format("%s.%s %s", module_name, programname, err)
        end
        return err
    else
        msg.Payload = payload
    end
    inject_message(msg)
end

return M

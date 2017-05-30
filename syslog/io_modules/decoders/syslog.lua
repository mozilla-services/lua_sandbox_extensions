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
  -- template = "<%PRI%>%TIMESTAMP% %HOSTNAME% %syslogtag:1:32%%msg:::sp-if-no-1st-sp%%msg%" -- RSYSLOG_TraditionalForwardFormat

  -- sub_decoders = {
    -- _programname_ (string) - Decoder module name or grammar module name
    -- kernel = "lpeg.linux.kernel", -- exports an lpeg grammar named 'syslog_grammar'
    -- nginx  = "decoders.nginx.access", -- decoder module name
  -- }

  -- When using sub decoders this stores the original log line in the message payload.
  -- payload_keep = false, -- default
}
```

## Functions

### decode

Decode and inject the resulting message

*Arguments*
- data (string) - syslog message
- default_headers (optional table) - Heka message table containing the default
  header values to use, if they are not populated by the decoder. If 'Fields'
  is specified it should be in the hashed based format see:
  http://mozilla-services.github.io/lua_sandbox/heka/message.html

*Return*
- (nil, string) or throws an error on invalid data or an inject message failure
    - nil - if the decode was successful
    - string - error message if the decode failed (e.g. no match)
--]]

-- Imports

local module_name   = ...
local module_cfg    = require "string".gsub(module_name, "%.", "_")
local syslog        = require "lpeg.syslog"

local cfg = read_config(module_cfg) or {}
assert(type(cfg) == "table", module_cfg .. " must be a table")
local template      = cfg.template or "<%PRI%>%TIMESTAMP% %HOSTNAME% %syslogtag:1:32%%msg:::sp-if-no-1st-sp%%msg%"
local grammar       = syslog.build_rsyslog_grammar(template)
local sub_decoders  = {}

for k,v in pairs(cfg.sub_decoders or {}) do
    if type(v) == "string" then
        if v:match("^decoders%.") then
            local decode = require(v).decode
            assert(type(decode) == "function", "sub_decoders, no decode function defined: " .. k)
            sub_decoders[k] = decode
        else
            local grammar = require(v).syslog_grammar
            assert(type(grammar) == "userdata", "sub_decoders, no grammar defined: " .. k)
            sub_decoders[k] = function(data, dh) -- dh will contain the original parsed syslog message
                local fields = grammar:match(data)
                if not fields then return "parse failed" end
                for k,v in pairs(fields) do
                    dh.Fields[k] = v
                end
                inject_message(dh)
            end
        end
    else
        error("sub_decoder, invalid type: " .. k)
    end
end

local pairs = pairs
local type  = type

local inject_message = inject_message

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local msg = {}

function decode(data, dh)
    local fields = grammar:match(data)
    if not fields then return "parse failed" end
    local programname = ""

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

    msg.Payload = fields.msg
    fields.msg = nil

    msg.Fields = fields

    if dh then
        msg.Uuid        = dh.Uuid
        msg.Logger      = dh.Logger
        if not msg.Hostname then msg.Hostname = dh.Hostname end
        if not msg.Timestamp then msg.Timestamp = dh.Timestamp end
        msg.Type        = dh.Type
        if not msg.Payload then msg.Payload = dh.Payload end
        msg.EnvVersion  = dh.EnvVersion
        if not msg.Pid then msg.Pid = dh.Pid end
        if not msg.Severity then msg.Severity = dh.Severity end

        if type(dh.Fields) == "table" then
            for k,v in pairs(dh.Fields) do
                if msg.Fields[k] == nil then
                    msg.Fields[k] = v
                end
            end
        end
    end

    local df = sub_decoders[programname]
    if df then
        local payload = msg.Payload
        if not cfg.payload_keep then msg.Payload = nil end
        return df(payload, msg)
    end
    inject_message(msg)
end

return M

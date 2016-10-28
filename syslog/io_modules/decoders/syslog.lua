-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Syslog Basic Decoder Module

## Decoder Configuration Table
```lua
-- template (string) - The 'template' configuration string from rsyslog.conf
-- see http://rsyslog-5-8-6-doc.neocities.org/rsyslog_conf_templates.html
-- Default:
-- template = "<%PRI%>%TIMESTAMP% %HOSTNAME% %syslogtag:1:32%%msg:::sp-if-no-1st-sp%%msg%" -- RSYSLOG_TraditionalForwardFormat
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
local syslog = require "lpeg.syslog"

local template  = read_config("template") or "<%PRI%>%TIMESTAMP% %HOSTNAME% %syslogtag:1:32%%msg:::sp-if-no-1st-sp%%msg%"
local grammar   = syslog.build_rsyslog_grammar(template)

local pairs = pairs
local type  = type

local inject_message = inject_message

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local msg = {}

function decode(data, dh)
    local fields = grammar:match(data)
    if not fields then return "parse failed" end

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
        fields.programname = fields.syslogtag.programname
        msg.Pid = fields.syslogtag.pid
        fields.syslogtag = nil
    end

    msg.Hostname = fields.hostname or fields.source
    fields.hostname = nil
    fields.source = nil

    msg.Payload = fields.msg
    fields.msg = nil

    msg.Fields = fields

    if dh then
        if not msg.Uuid then msg.Uuid = dh.Uuid end
        if not msg.Logger then msg.Logger = dh.Logger end
        if not msg.Hostname then msg.Hostname = dh.Hostname end
        if not msg.Timestamp then msg.Timestamp = dh.Timestamp end
        if not msg.Type then msg.Type = dh.Type end
        if not msg.Payload then msg.Payload = dh.Payload end
        if not msg.EnvVersion then msg.EnvVersion = dh.EnvVersion end
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

    inject_message(msg)
end

return M

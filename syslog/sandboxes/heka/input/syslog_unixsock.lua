-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

-- Author: Mathieu Parent <math.parent@gmail.com>

--[[
# Syslog UNIX socket Input

## Sample Configuration
```lua
filename            = "syslog_unixsock.lua"
instruction_limit   = 0

-- socket_path (string) - UNIX socket path. "auto" means use sd_listen_fds()
-- under systemd, and /dev/log otherwise.
-- socket_path = "auto"

-- template (string) - The 'template' configuration string from rsyslog.conf
-- see http://rsyslog-5-8-6-doc.neocities.org/rsyslog_conf_templates.html
-- template = "<%PRI%>%TIMESTAMP% %syslogtag:1:32%%msg:::sp-if-no-1st-sp%%msg%"
```
--]]

local syslog = require "lpeg.syslog"
local socket = require "socket"
socket.unix = require "socket.unix"
local systemd_ok, systemd_daemon = pcall(require, "systemd.daemon")

local socket_path   = read_config("socket_path") or "auto"
local template      = read_config("template") or "<%PRI%>%TIMESTAMP% %syslogtag:1:32%%msg:::sp-if-no-1st-sp%%msg%"

local grammar       = syslog.build_rsyslog_grammar(template)
local is_running    = is_running

local msg = {
Timestamp   = nil,
Type        = read_config("type"),
Hostname    = nil,
Payload     = nil,
Pid         = nil,
Severity    = nil,
Fields      = nil
}

local err_msg = {
    Type    = "error",
    Payload = nil,
}

local u = assert(socket.unix.udp())
if socket_path == 'auto' then
    if systemd_ok and systemd_daemon.booted() then
        local sd_fds = systemd_daemon.listen_fds(0)
        if sd_fds < 1 then
            error('Failed to acquire systemd socket')
        end
        -- We use first fd
        local fd = systemd_daemon.LISTEN_FDS_START
        -- TODO Check systemd_daemon.is_socket_unix(fd, SOCK_DGRAM, -1, '/run/systemd/journal/syslog', 0)
        u:setfd(fd)
    else
        -- Note: /var/run/log on BSD
        assert(u:bind('/dev/log'))
    end
else
    assert(u:bind(socket_path))
end

function process_message()
    while is_running() do
        local data, path = u:receivefrom()
        if data then
            local fields = grammar:match(data)
            if fields then
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

                -- fields.sender_path = path

                msg.Fields = fields
                pcall(inject_message, msg)
            end
        else
            err_msg.Payload = path
            pcall(inject_message, err_msg)
        end
    end
    return 0
end

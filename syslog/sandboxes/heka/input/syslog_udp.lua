-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Syslog UDP and UNIX socket Input

## Sample Configuration #1
```lua
filename            = "syslog_udp.lua"
instruction_limit   = 0

-- address (string) - an IP address (* for all interfaces), or a path to an UNIX socket
-- Default:
-- address = "127.0.0.1"

-- port (integer) - IP port to listen on (ignored for UNIX socket)
-- Default:
-- port = 514

-- sd_fd (integer) - If set, systemd socket activation is tryed
-- Default:
-- sd_fd = nil

-- template (string) - The 'template' configuration string from rsyslog.conf
-- see http://rsyslog-5-8-6-doc.neocities.org/rsyslog_conf_templates.html
-- Defaults:
-- template = "<%PRI%>%TIMESTAMP% %HOSTNAME% %syslogtag:1:32%%msg:::sp-if-no-1st-sp%%msg%" -- RSYSLOG_TraditionalForwardFormat
-- template = "<%PRI%>%TIMESTAMP% %syslogtag:1:32%%msg:::sp-if-no-1st-sp%%msg%" -- for UNIX socket

-- send_decode_failures (bool) - If true, any decode failure will inject a
-- message of Type "error", with the Payload containing the error, and with the
-- "data" field containing the original, undecoded Payload.
```

## Sample Configuration #2: system syslog with systemd socket activation
```lua
filename            = "syslog_udp.lua"
instruction_limit   = 0

address             = "/dev/log"
sd_fd               = 0
```
--]]

local syslog = require "lpeg.syslog"
local socket = require "socket"

local address       = read_config("address") or "127.0.0.1"
local port          = read_config("port") or 514
local sd_fd         = read_config("sd_fd")
local hostname_keep = read_config("hostname_keep")
local template      = read_config("template")
local is_unixsock   = address:sub(1,1) == '/'
if not template then
    if is_unixsock then
        template = "<%PRI%>%TIMESTAMP% %syslogtag:1:32%%msg:::sp-if-no-1st-sp%%msg%"
    else
        template = "<%PRI%>%TIMESTAMP% %HOSTNAME% %syslogtag:1:32%%msg:::sp-if-no-1st-sp%%msg%"
    end
end
local grammar       = syslog.build_rsyslog_grammar(template)
local is_running    = is_running

local msg = {
    Timestamp = nil,
    Type      = read_config("type"),
    Hostname  = nil,
    Payload   = nil,
    Pid       = nil,
    Severity  = nil,
    Fields    = nil
}

local err_msg = {
    Type    = "error",
    Payload = nil,
    Fields  = {
        data = nil
    }
}

local server
if is_unixsock then
    socket.unix = require "socket.unix"
    server = assert(socket.unix.udp())
else
    server = assert(socket.udp())
end

if sd_fd ~= nil then
    local systemd_ok, systemd_daemon = pcall(require, "systemd.daemon")
    if systemd_ok and systemd_daemon.booted() then
        local sd_fds = systemd_daemon.listen_fds(0)
        if sd_fds < 1 then
            error('Failed to acquire systemd socket')
        end
        local fd = systemd_daemon.LISTEN_FDS_START + sd_fd
        -- TODO Check systemd_daemon.is_socket_unix(fd, SOCK_DGRAM, -1, '/run/systemd/journal/syslog', 0)
        server:setfd(fd)
    else
        sd_fd = nil
    end
end
if sd_fd == nil then
    if is_unixsock then
        assert(server:bind(address))
    else
        assert(server:setsockname(address, port))
        server:settimeout(1)
    end
end

function process_message()
    while is_running() do
        local data, remote, port = server:receivefrom()
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

                if not is_unixsock then
                    fields.sender_ip = remote
                    fields.sender_port = {value = port, value_type = 2}
                -- else fields.sender_path = remote
                end

                msg.Fields = fields
                pcall(inject_message, msg)
            elseif send_decode_failures then
                err_msg.Type = "error.decode"
                err_msg.Payload = "Unable to decode data"
                err_msg.Fields.data = data
                pcall(inject_message, err_msg)
            end
        elseif remote ~= "timeout" then
            err_msg.Type = "error.closed"
            err_msg.Payload = remote
            err_msg.Fields.data = nil
            pcall(inject_message, err_msg)
        end
    end
    return 0
end

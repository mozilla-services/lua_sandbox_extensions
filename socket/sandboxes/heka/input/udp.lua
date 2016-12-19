-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# UDP and UNIX Socket Input

## Sample Configuration #1
```lua
filename            = "udp.lua"
instruction_limit   = 0

-- address (string) - An IP address (* for all interfaces), or a path to a UNIX 
-- socket.
-- Default:
-- address = "127.0.0.1"

-- port (integer) - IP port to listen on (ignored for UNIX socket).
-- Default:
-- port = 514

-- sd_fd (integer) - If set, file descriptor passed by the system manager.
-- Default:
-- sd_fd = nil

-- default_headers (table) - Sets the message headers to these values if they
-- are not set by the decoder.
-- This input will always default the Fields.sender_ip and Fields.sender_port
-- for non UNIX sockets.
-- Default:
-- default_headers = nil

-- Specify a module that will decode the raw data and inject the resulting message.
-- Default:
-- decoder_module = "decoders.heka.protobuf"

-- send_decode_failures (bool) - When true a decode failure will inject a
-- message with the following structure:
-- msg.Type = "error.<category>"
-- msg.Payload = "<error message>"
-- msg.Fields.data = "<data that failed decode>"
-- Default
-- send_decode_failures = false


## Sample Configuration #2: system syslog with systemd socket activation
# See https://www.freedesktop.org/wiki/Software/systemd/syslog/
filename             = "udp.lua"
instruction_limit    = 0
address              = "/dev/log"
sd_fd                = 0
decoder_module       = "decoders.syslog"
template             = "<%PRI%>%TIMESTAMP% %syslogtag:1:32%%msg:::sp-if-no-1st-sp%%msg%"
send_decode_failures = true
```
--]]
local socket = require "socket"

local address               = read_config("address") or "127.0.0.1"
local is_unixsock           = address:sub(1,1) == "/"
local port                  = read_config("port") or 514
local sd_fd                 = read_config("sd_fd")
local default_headers       = read_config("default_headers")
assert(default_headers == nil or type(default_headers) == "table", "invalid default_headers cfg")

local decoder_module = read_config("decoder_module") or "decoders.heka.protobuf"
local decode = require(decoder_module).decode
if not decode then
    error(decoder_module .. " does not provide a decode function")
end
local send_decode_failures = read_config("send_decode_failures")

local err_msg = {
    Type    = nil,
    Payload = nil,
    Fields  = {
        data = nil
    }
}

local server
if sd_fd ~= nil then
    local systemd_ok, systemd_daemon = pcall(require, "systemd.daemon")
    if not systemd_ok then
        print("Unable to acquire systemd socket: " .. systemd_daemon)
        sd_fd = nil
    elseif not systemd_daemon.booted() then
        print("Unable to acquire systemd socket: not running the systemd init system")
        sd_fd = nil
    else
        local sd_fds = systemd_daemon.listen_fds(0)
        if sd_fds < 1 then
            -- This one is fatal
            error("Unable to acquire systemd socket: no socket passed")
        end
        local fd = systemd_daemon.LISTEN_FDS_START + sd_fd
        socket.unix = require "socket.unix"
        server = assert(socket.unix.udp())
        server:setfd(fd)
    end
end

if sd_fd == nil then
    if  is_unixsock then
        socket.unix = require "socket.unix"
        server = assert(socket.unix.udp())
        require "os"
        os.remove(address)
        assert(server:bind(address))
    else
        server = assert(socket.udp())
        assert(server:setsockname(address, port))
        server:settimeout(1)
        if not default_headers then default_headers = {} end
        local port = {value = 0, value_type = 2}
        default_headers.Fields = { sender_port = port }
        err_msg.Fields.sender_port = port
    end
end

local is_running = is_running
function process_message()
    while is_running() do
        local data, remote, port = server:receivefrom()
        if data then
            if not is_unixsock then
                default_headers.Fields.sender_ip = remote
                default_headers.Fields.sender_port.value = port
            end

            local ok, err = pcall(decode, data, default_headers)
            if (not ok or err) and send_decode_failures then
                err_msg.Type = "error.decode"
                err_msg.Payload = err
                err_msg.Fields.data = data
                if not is_unixsock then 
                    err_msg.Fields.sender_ip = remote
                    -- port is already set in the shared table
                end
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

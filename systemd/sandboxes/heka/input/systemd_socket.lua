-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Systemd Socket Input
Syslog with systemd socket activation

## Sample Configuration
```lua
filename            = "systemd_socket.lua"
instruction_limit   = 0

-- sd_fd (integer) - systemd socket activation file descriptor
-- Default:
-- sd_fd = 0

-- default_headers (table) - Sets the message headers to these values if they
-- are not set by the decoder
-- Default:
-- default_headers = nil

-- Specify a module that will decode the raw data and inject the resulting message.
-- Default:
-- decoder_module = "decoders.syslog"

-- send_decode_failures (bool) - When true a decode failure will inject a
-- message with the following structure:
-- msg.Type = "error.<category>"
-- msg.Payload = "<error message>"
-- msg.Fields.data = "<data that failed decode>"
-- Default
-- send_decode_failures = false
```
--]]
local sdd   = require "systemd.daemon"
local unix  = require "socket.unix"

local default_headers = read_config("default_headers")
assert(default_headers == nil or type(default_headers) == "table", "invalid default_headers cfg")

local decoder_module = read_config("decoder_module") or "decoders.syslog"
local decode = require(decoder_module).decode
if not decode then
    error(decoder_module .. " does not provide a decode function")
end
local send_decode_failures = read_config("send_decode_failures")

local sd_fd = read_config("sd_fd") or 0

if not sdd.booted() then error("systemd is not running") end
local sd_fds = sdd.listen_fds(0)
if sd_fds < 1 then error('Failed to acquire systemd socket') end
local fd = sdd.LISTEN_FDS_START + sd_fd
-- TODO Check sdd.is_socket_unix(fd, SOCK_DGRAM, -1, '/run/systemd/journal/syslog', 0)

local server = assert(unix.udp())
server:setfd(fd)

local err_msg = {
    Type    = nil,
    Payload = nil,
    Fields  = {
        data = nil
    }
}

local is_running = is_running
function process_message()
    while is_running() do
        local data, remote, port = server:receivefrom()
        if data then
            local ok, err = pcall(decode, data, default_headers)
            if (not ok or err) and send_decode_failures then
                err_msg.Type = "error.decode"
                err_msg.Payload = err
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

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# UDP and UNIX Socket Input

## Sample Configuration
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

-- default_headers (table) - Sets the message headers to these values if they
-- are not set by the decoder.
-- This input will always default the Fields.sender_ip and Fields.sender_port
-- for non UNIX sockets.
-- Default:
-- default_headers = nil

-- printf_messages = -- see: https://mozilla-services.github.io/lua_sandbox_extensions/lpeg/modules/lpeg/printf.html

-- Specifies a module that will decode the raw data and inject the resulting message.
-- Supports the same syntax as an individual sub decoder
-- see: https://mozilla-services.github.io/lua_sandbox_extensions/lpeg/io_modules/lpeg/sub_decoder_util.html
-- Default:
-- decoder_module = "decoders.heka.protobuf"

-- send_decode_failures (bool) - When true a decode failure will inject a
-- message with the following structure:
-- msg.Type = "error.<category>"
-- msg.Payload = "<error message>"
-- msg.Fields.data = "<data that failed decode>"
-- Default
-- send_decode_failures = false
```
--]]
local socket = require "socket"
local sdu       = require "lpeg.sub_decoder_util"
local decode    = sdu.load_sub_decoder(read_config("decoder_module") or "decoders.heka.protobuf", read_config("printf_messages"))

local address               = read_config("address") or "127.0.0.1"
local is_unixsock           = address:sub(1,1) == "/"
local port                  = read_config("port") or 514
local default_headers       = read_config("default_headers")
assert(default_headers == nil or type(default_headers) == "table", "invalid default_headers cfg")
local send_decode_failures = read_config("send_decode_failures")

local err_msg = {
    Type    = nil,
    Payload = nil,
    Fields  = {
        data = nil
    }
}

local server
if is_unixsock then
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

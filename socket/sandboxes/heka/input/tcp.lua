-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# TCP Input (new line delimited)
todo: when more than line splitting is needed the file should be read in chunks
and passed to a generic splitter buffer with a token/match specification and a
find function similar to the Heka stream reader.

## Sample Configuration
```lua
filename = "tcp.lua"
instruction_limit = 0

-- address (string) - an IP address (* for all interfaces)
-- Default:
-- address = "127.0.0.1"

-- port (integer) - IP port to listen on (ignored for UNIX socket)
-- Default:
-- port = 5566

-- default_headers (table) - Sets the message headers to these values if they
-- are not set by the decoder.
-- This input will always default the Hostname header to the source IP address.
-- Default:
-- default_headers = nil

-- Specifies a module that will decode the raw data and inject the resulting message.
-- Default:
-- decoder_module = "decoders.payload"

-- Boolean, if true, any decode failure will inject a  message of Type "error",
-- with the Payload containing the error.
-- Default:
-- send_decode_failures = false

ssl_params = {
  mode = "server",
  protocol = "tlsv1",
  key = "/etc/hindsight/certs/serverkey.pem",
  certificate = "/etc/hindsight/certs/server.pem",
  cafile = "/etc/hindsight/certs/CA.pem",
  verify = {"peer", "fail_if_no_peer_cert"},
  options = {"all", "no_sslv3"}
}
```
--]]

require "coroutine"
local socket = require "socket"
require "string"
require "table"
local sdu       = require "lpeg.sub_decoder_util"
local decode    = sdu.load_sub_decoder(read_config("decoder_module") or "decoders.payload", read_config("printf_messages"))

local address           = read_config("address") or "127.0.0.1"
local port              = read_config("port") or 5566
local default_headers   = read_config("default_headers") or {}
assert(type(default_headers) == "table", "invalid default_headers cfg")
local send_decode_failures  = read_config("send_decode_failures")
local ssl_params = read_config("ssl_params")

local ssl_ctx = nil
local ssl = nil
if ssl_params then
    ssl = require "ssl"
    ssl_ctx = assert(ssl.newcontext(ssl_params))
end

local server = assert(socket.bind(address, port))
server:settimeout(0)
local threads = {}
local sockets = {server}
local is_running = is_running

local err_msg = {
    Type    = "error.decode",
    Payload = nil,
    Fields  = {
        data = nil
    }
}

local function handle_client(client, caddr, cport)
    local chunks
    client:settimeout(0)
    while client do
        -- store the partial in a table instead of prefixing it in the receive buffer
        -- if there is more than one partial concatenating them later uses less memory
        local buf, err, partial = client:receive("*l")
        if buf and chunks then
            table.insert(chunks, buf)
            buf = table.concat(chunks)
            chunks = nil
        elseif partial then
            if not chunks then chunks = {} end
            table.insert(chunks, partial)
        end

        if buf then
            default_headers.Hostname = caddr
            local ok, err1 = pcall(decode, buf, default_headers)
            if (not ok or err1) and send_decode_failures then
                err_msg.Payload = err1
                err_msg.Fields.data = data
                pcall(inject_message, err_msg)
            end
        end

        if err == "closed" then break end
        coroutine.yield()
    end
end

function process_message()
    while is_running() do
        local ready = socket.select(sockets, nil, 1)
        if ready then
            for _, s in ipairs(ready) do
                if s == server then
                    local client = s:accept()
                    if client then
                        local caddr, cport = client:getpeername()
                        if not caddr then
                            caddr = "unknown"
                            cport = 0
                        end
                        if ssl_ctx then
                            client = ssl.wrap(client, ssl_ctx)
                            client:dohandshake()
                        end
                        sockets[#sockets + 1] = client
                        threads[client] = coroutine.create(
                            function() handle_client(client, caddr, cport) end)
                    end
                else
                    if threads[s] then
                        local status = coroutine.resume(threads[s])
                        if not status then
                            s:close()
                            for i = #sockets, 2, -1 do
                                if s == sockets[i] then
                                    table.remove(sockets, i)
                                    break
                                end
                            end
                            threads[s] = nil
                        end
                    end
                end
            end
        end
    end
    return 0
end

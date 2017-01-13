-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Compatible TCP Output

## Sample Configuration
```lua
filename        = "heka_tcp.lua"
message_matcher = "TRUE"

address = "127.0.0.1"
port    = 5565
timeout = 10

ssl_params = {
  mode = "client",
  protocol = "tlsv1",
  key = "/etc/hindsight/certs/clientkey.pem",
  certificate = "/etc/hindsight/certs/client.pem",
  cafile = "/etc/hindsight/certs/CA.pem",
  verify = "peer",
  options = {"all", "no_sslv3"}
}
```
--]]

local socket = require "socket"

local address = read_config("address") or "127.0.0.1"
local port = read_config("port") or 5565
local timeout = read_config("timeout") or 10
local ssl_params = read_config("ssl_params")

local ssl_ctx = nil
local ssl = nil
if ssl_params then
    require "table"
    ssl = require "ssl"
    ssl_ctx = assert(ssl.newcontext(ssl_params))
end

local function create_client()
    local c, err = socket.connect(address, port)
    if c then
        c:setoption("tcp-nodelay", true)
        c:setoption("keepalive", true)
        c:settimeout(timeout)
        if ssl_ctx then
            c, err = ssl.wrap(c, ssl_ctx)
            if c then
                c:dohandshake()
            end
        end
    end
    return c, err
end

local client, err = create_client()

local function send_message(msg)
    local i = 1
    for retry = 1, 3 do
        local len, err, i = client:send(msg, i)
        if len then
            return 0
        end
        i = i + 1
    end
    client:close()
    client = nil
    return -3, err
end

function process_message()
    if not client then
        client, err = create_client()
    end
    if not client then return -3, err end -- retry indefinitely
    return send_message(read_message("framed"))
end

function timer_event(ns)
    -- no op
end

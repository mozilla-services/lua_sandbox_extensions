-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Compatible TCP Output

## Sample Configuration
```lua
filename        = "heka_tcp.lua"
message_matcher = "TRUE"
drop_message_on_error = false, -- default will retry indefinitely

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

local time   = require "os".time
local socket = require "socket"

local address = read_config("address") or "127.0.0.1"
local port = read_config("port") or 5565
local timeout = read_config("timeout") or 10
local ssl_params = read_config("ssl_params")
local err_return = -3 -- retry indefinitely
if read_config("drop_message_on_error") then err_return = -2 end -- silently drop/skip the message

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

local client, err
local time_t = 0
function process_message()
    if not client then
        local t = time()
        if t - time_t > 0 then
            client, err = create_client()
            time_t = t
        end
    end
    if not client then return err_return, err end

    local len, err = client:send(read_message("framed"))
    if not len then
        client:close()
        client = nil
        return err_return, err
    end
    return 0
end

function timer_event(ns)
    -- no op
end

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Write a InfluxDB Line Protocol Payload to the the InfluxDB database


#### Sample Configuration

```lua
filename                = "influx_output.lua"
message_matcher         = "Logger =~ '^analysis%.influx_'"
read_queue              = "analysis"
ticker_interval         = 60
shutdown_on_terminate   = true
preserve_data           = true

url         = "
user        = ""
_password   = ""
timeout     = 10 -- default

```
--]]
data = {}

require("string")
require("table")
local http      = require("socket.http")
local https     = require("ssl.https")
local ltn12     = require("ltn12")
local mime      = require("mime")

local url       = read_config("url") or  error"url configuration required"
local user      = read_config("user") or error"user configuration required"
local _password = read_config("_password") or error"_password configuration required"
http.TIMEOUT    = read_config("timeout") or 10


local req_headers = {
    ["user-agent"]      = http.USERAGENT,
    ["content-type"]    = "application/octet-stream",
    ["content-length"]  = 0,
    ["authorization"]   = "Basic " .. mime.b64(user .. ":" .. _password)
}

local err = nil
function process_message()
    if err then
        timer_event()
        return -3, err
    end
    data[#data + 1] = read_message("Payload")
    return 0
end


function timer_event(ns, shutdown)
    local content = table.concat(data, "\n")
    req_headers["content-length"] = #content

    local request = {
        url         = url,
        method      = "POST",
        source      = ltn12.source.string(content),
        headers     = req_headers,
        sink        = nil, -- discard response
    }
    local r, c = https.request(request)

    if not r or c ~= 204 then
        err = tostring(c)
        if c == 400 then error("malformed request, this is a plugin bug") end
    else
        err     = nil
        data    = {}
    end
end

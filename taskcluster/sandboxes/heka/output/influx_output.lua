-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Write a InfluxDB Line Protocol Payload to the the InfluxDB database


#### Sample Configuration

```lua
filename               	= "influx_output.lua"
message_matcher        	= "Logger =~ '^analysis%.influx_'"
read_queue             	= "analysis"
ticker_interval		    = 0
shutdown_on_terminate  	= true

url         = "
user        = ""
_password   = ""
timeout     = 10 -- default

```
--]]
require("string")
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

function process_message()
    local s = read_message("Payload")
    req_headers["content-length"] = #s

    local request = {
        url         = url,
        method      = "POST",
        source      = ltn12.source.string(s),
        headers     = req_headers,
        sink        = nil, -- discard response
    }
    local r, c = https.request(request)

    if not r or c ~= 204 then
        return -3, tostring(c)
    end
    return 0
end


function timer_event(ns, shutdown)
    -- no op
end

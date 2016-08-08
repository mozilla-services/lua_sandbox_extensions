-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Generated Landfill to nginx_moz_ingest

Takes the Heka generated telemetry landfill messages and turns then back
into HTTP requests to test the nginx_moz_ingest module.

#### Sample Configuration

```lua
filename        = "moz_telemetry_http.lua"
message_matcher = "Type == 'heka.httpdata.request'"
ticker_interval = 0

```
--]]


require "string"
local ltn12     = require "ltn12"
local socket    = require "socket"
local http      = require "socket.http"
local address   = read_config("address") or "127.0.0.1"
local port      = read_config("port") or 8880
http.TIMEOUT    = read_config("timeout") or 10


local req_headers = {
    ["user-agent"]      = http.USERAGENT,
    ["content-type"]    = "application/x-gzip",
    ["content-length"]  = 0,
    ["host"]            = address,
}

function process_message()
    local s = read_message("Fields[submission]")
    req_headers["content-length"] = #s
    local request = {
        url = string.format("http://%s:%d%s", address, port, read_message("Fields[Path]")),
        method = "POST",
        source = ltn12.source.string(s),
        headers = req_headers,
    }
    local r, c, h = http.request(request)

    if not r or c ~= 200 then
        return -1, tostring(c)
    end

    return 0
end


function timer_event(ns, shutdown)
end

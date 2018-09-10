-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# iprepd Output Plugin

Sends iprepd events to Mozilla iprepd IP reputation service using a
hawk/JSON request. This output plugin currently only supports submitting
IP violations to the /violations/ endpoint.

https://github.com/mozilla-services/iprepd

## Sample Configuration
```lua
filename = "moz_security_iprepd.lua"
message_matcher = "Type == 'iprepd'"

-- Configuration for pushing violations to iprepd
iprepd = {
   base_url     = "https://iprepd.prod.mozaws.net", -- NB: no trailing slash
   id           = "fxa_heavy_hitters", -- hawk ID
   _key         = "hawksecret" -- hawk secret
}
```
--]]

local client_cfg = read_config("iprepd") or error("no iprepd configuration specified")

local string    = require("string")
local http      = require("socket.http")
local https     = require("ssl.https")
local url       = require("socket.url")
local ltn12     = require("ltn12")
local cjson     = require("cjson")

local hawk = require "hawk"
local hawkhdr = {}


local function get_port(parsed_url)
    if parsed_url.port then
        return tonumber(parsed_url.port)
    elseif parsed_url.scheme and parsed_url.scheme == "http" then
        return 80
    elseif parsed_url.scheme and parsed_url.scheme == "https" then
        return 443
    else
        error("no scheme or port found for base_url")
    end
end


local function configure_client()
    if not client_cfg.base_url then
        error("configuration missing base_url")
    end
    if not client_cfg.id or not client_cfg._key then
        error("configuration missing hawk credentials")
    end

    local parsed_base = url.parse(client_cfg.base_url)
    client_cfg.host = parsed_base.host
    client_cfg.port = get_port(parsed_base)

    if parsed_base.scheme == "https" then
        client_cfg.requestor = https
    else
        client_cfg.requestor = http
    end

    hawkhdr = hawk.new(client_cfg.id, client_cfg._key, client_cfg.host, client_cfg.port)
end


local function json_request(method, uri, body)
    local headers = {
        Authorization = hawkhdr:get_header(method, uri, body, "application/json"),
        Host = string.format("%s:%d", client_cfg.host, client_cfg.port),
        ["Content-Type"] = "application/json",
        ["Content-Length"] = #body,
    }

    local response = {}
    if not client_cfg.requestor then
        error("no requestor set in configuration")
    end
    local r, code = client_cfg.requestor.request({
        method = method,
        url = string.format("%s%s", client_cfg.base_url, uri),
        headers = headers,
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(response)
    })

    if type(code) == "string" then
        -- request could not be made, code will contain an error string (e.g., connection refused)
        return false, code
    elseif type(code) == "number" and code >= 400 then
        return false, string.format("request failed with response code %d", code)
    end
    return true, ""
end

configure_client()

function process_message()
    violations = read_message("Fields[violations]")
    if not violations or type(violations) ~= "string" then
        return -1, "invalid argument for violations"
    end
    -- send violation notices in groups of <= 100
    local ok, ret = pcall(cjson.decode, violations)
    if ok then
        for i=1,#ret,100 do
            local ok, msg = json_request("PUT", "/violations", cjson.encode({unpack(ret, i, i+99)}))
            if not ok then return -1, msg end
        end
    else
        return -1, ret
    end
    return 0
end


function timer_event(ns)
    -- no op
end

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Tigerblood Output Plugin

Sends tigerblood events to Mozilla Tigerblood IP reputation service using a
hawk/JSON request.

https://github.com/mozilla-services/tigerblood

## Sample Configuration
```lua
filename = "moz_security_tigerblood.lua"
message_matcher = "Type == 'tigerblood'"

-- Configuration for pushing violations to Tigerblood
tigerblood = {
   base_url     = "https://tigerblood.prod.mozaws.net", -- NB: no trailing slash
   id           = "fxa_heavy_hitters", -- hawk ID
   key          = "hawksecret", -- hawk secret
}
```
--]]

local client_cfg = read_config("tigerblood") or error("no tigerblood configuration specified")

local string    = require("string")
local table     = require("table")
local digest    = require("openssl").digest
local hmac      = require("openssl").hmac
local random    = require("openssl").random
local mime      = require("mime")
local os        = require("os")
local http      = require("socket.http")
local https     = require("ssl.https")
local url       = require("socket.url")
local ltn12     = require("ltn12")
local cjson     = require("cjson")

local function url_escape(s)
    return s:gsub("+", "-"):gsub("/", "_"):gsub("=", "")
end

local function nonce(size)
    return url_escape(mime.b64(random(size)))
end

local function supported_hash(algorithm)
    return algorithm == "sha256"
end

local function hash_payload(payload, algorithm, content_type)
    if not supported_hash(algorithm) then
        error("unsupported hash algorithm")
    end

    local normalized = "hawk.1.payload"
    normalized = string.format("%s\n%s", normalized, string.lower(content_type))
    normalized = string.format("%s\n%s\n", normalized, payload)
    return mime.b64(digest.digest(algorithm, normalized, true))
end

local function normalize_string(artifacts)
    local normalized = {
        "hawk.1.header",
        artifacts.ts,
        artifacts.nonce,
        string.upper(artifacts.method),
        artifacts.resource,
        string.lower(artifacts.host),
        artifacts.port,
        artifacts.hash,
        "",
    }
    return string.format("%s\n", table.concat(normalized, "\n"))
end

local function calculate_mac(artifacts)
    if not supported_hash(client_cfg.algorithm) then
        error("unsupported hash algorithm")
    end
    return mime.b64(hmac.hmac(client_cfg.algorithm, normalize_string(artifacts),
        client_cfg.key, true))
end

local function hawk_artifacts(method, resource)
    return {
        method = method,
        host = client_cfg.host,
        port = client_cfg.port,
        resource = resource,
        ts = os.time(),
        nonce = nonce(6),
    }
end

local function hawk_options(payload)
    return {
        payload = payload,
        content_type = "application/json",
    }
end

local function hawk_header(artifacts, options)
    if options.payload and options.content_type then
        artifacts.hash = hash_payload(options.payload, client_cfg.algorithm, options.content_type)
    end

    local mac = calculate_mac(artifacts)
    local header = string.format("Hawk id=\"%s\", ts=\"%s\", nonce=\"%s\"",
        client_cfg.id, artifacts.ts, artifacts.nonce)

    if artifacts.hash then
        header = string.format("%s, hash=\"%s\"", header, artifacts.hash)
    end

    return string.format("%s, mac=\"%s\"", header, mac)
end

local function get_port(parsed_url)
    if parsed_url.port then
        return parsed_url.port
    elseif parsed_url.scheme and parsed_url.scheme == "http" then
        return 80
    elseif parsed_url.scheme and parsed_url.scheme == "https" then
        return 443
    else
        error("no scheme or port found for base_url")
    end
end

local function configure_client()
    if not client_cfg.algorithm then
        client_cfg.algorithm = "sha256"
    end

    if not client_cfg.base_url then
        error("configuration missing base_url")
    end
    if not client_cfg.id or not client_cfg.key then
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
end

local function json_request(method, uri, body)
    local headers = {
        Authorization = hawk_header(hawk_artifacts(method, uri), hawk_options(body)),
        Host = string.format("%s:%s", client_cfg.host, client_cfg.port),
        ["Content-Type"] = "application/json",
        ["Content-Length"] = #body,
    }

    local response = {}
    if not client_cfg.requestor then
        error("no requestor set in configuration")
    end
    local r, code, resp_headers = client_cfg.requestor.request({
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
    local ok, msg = json_request("PUT", "/violations/", violations)
    if not ok then
        return -1, msg
    end
    return 0
end

function timer_event(ns)
    -- no op
end

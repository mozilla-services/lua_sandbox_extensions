-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Tigerblood Output

Sends tigerblood events to Mozilla Tigerblood IP reputation service.

https://github.com/mozilla-services/tigerblood

## Sample Configuration
```lua
filename = "moz_security_tigerblood.lua"
message_matcher = "Type == 'tigerblood'"

-- config for publishing to IP Reputation
config = {
   base_url = "https://tigerblood.prod.mozaws.net", -- NB: no trailing slash
   id = "fxa_heavy_hitters", -- hawk ID
   _key = "8eb54d0469ef000f8819a248c3f4465dc506bb2ad339aaa09466644b2214ffc8", -- hawk secret
}
```
--]]

-- IP reputation output config
local client_cfg = read_config("config") or error("No ip reputation client config specified")

-- Hawk signing

local string = require("string")
local table = require("table")
local digest = require("openssl").digest
local hmac = require("openssl").hmac
local random = require("openssl").random
local mime = require("mime")
local os = require("os")

local function url_escape(s)
    return s:gsub("+", "-"):gsub("/", "_"):gsub("=", "")
end

-- returns a url safe base 64 nonce
local function nonce(size)
    return url_escape(mime.b64(random(size)))
end

-- openssl supports more but just sha256 for now
local function supported_hash(algorithm)
    return algorithm == "sha256"
end

-- hash the normalized hawk payload string
local function hash_payload(payload, algorithm, content_type)
    if not supported_hash(algorithm) then
        error("Unsupported algorithm.")
    end

    local normalized = "hawk.1.payload"
    if content_type then
        normalized = string.format("%s\n%s", normalized, string.lower(content_type))
    end
    if payload then
        normalized = string.format("%s\n%s", normalized, payload)
    end
    normalized = string.format("%s\n", normalized)

    return mime.b64(digest.digest(algorithm, normalized, true)) -- digest w/ true to return binary
end


-- returns a normalized hawk header
local function normalize_string(artifacts)
    local normalized = {
        "hawk.1.header",
        artifacts.ts,
        artifacts.nonce,
        string.upper(artifacts.method),
        artifacts.resource,
        string.lower(artifacts.host),
        artifacts.port
    }

    if artifacts.hash then
        table.insert(normalized, artifacts.hash)
    else
        table.insert(normalized, "")
    end

    if artifacts.ext then
        local ext = artifacts.ext:gsub("\\", "\\\\"):gsub("\n", "\\n")
        table.insert(normalized, ext)
    else
        table.insert(normalized, "")
    end

    if artifacts.app then
        table.insert(normalized, artifacts.app)
        if artifacts.dlg then
            table.insert(normalized, artifacts.dlg)
        else
            table.insert(normalized, "")
        end
    end

    return string.format("%s\n", table.concat(normalized, "\n"))
end

local function calculate_mac(credentials, artifacts)
    if not supported_hash(credentials.algorithm) then
        error("Unsupported algorithm.")
    end

    local normalized = normalize_string(artifacts)

    return mime.b64(hmac.hmac(credentials.algorithm, normalized, credentials._key, true)) -- true to return binary
end


-- returns a hawk Authorization header
local function hawk_header(credentials, artifacts, options)
    local mac_artifacts = {
        method = artifacts.method,
        host = artifacts.host,
        port = artifacts.port,
        resource = artifacts.resource,
        ts = artifacts.ts or os.time(),
        nonce = artifacts.nonce or nonce(6), -- six b64 chars
        app = artifacts.app,
        dlg = artifacts.dlg,
    }

    if options.ext then
        mac_artifacts.ext = options.ext
    end

    if options.payload then
        mac_artifacts.hash = hash_payload(options.payload, credentials.algorithm, options.content_type)
    end

    local mac = calculate_mac(credentials, mac_artifacts)

    local header = string.format("Hawk id=\"%s\", ts=\"%s\", nonce=\"%s\"",  credentials.id, mac_artifacts.ts, mac_artifacts.nonce)

    if mac_artifacts.hash then
        header = string.format("%s, hash=\"%s\"", header, mac_artifacts.hash)
    end
    if options.ext then
        header = string.format("%s, ext=\"%s\"", header, mac_artifacts.ext)
    end

    header = string.format("%s, mac=\"%s\"", header, mac)

    return header
end

-- IP Reputation Output

local http = require("socket.http")
local https = require("ssl.https")
local url = require("socket.url")
local ltn12 = require("ltn12")
local cjson = require("cjson")

local client_config = { -- config params set via configure
    base_url = nil,
    id = nil,
    _key = nil,
    algorithm = "sha256",
    requestor = nil,
}

local computed_client_config = { -- config params computed from config
    host = nil,
    post = nil,
}

-- private function for parsing the port out of a URL
local function get_port(parsed_url)
    if parsed_url["port"] then
        return parsed_url["port"]
    elseif parsed_url["scheme"] and parsed_url["scheme"] == "http" then
        return 80
    elseif parsed_url["scheme"] and parsed_url["scheme"] == "https" then
        return 443
    else
        error("No scheme or port found for base_url.")
    end
end

-- sets client config values; must be called before making requests
-- example usage:
--
-- configure_client({
--    base_url = "http://localhost:8080", -- tigerblood service url w/o slash
--    id = "root", -- hawk ID
--    _key = "toor", -- hawk key
-- })
--
local function configure_client(new_client_config)
    client_config["base_url"] = new_client_config["base_url"];
    client_config["id"] = new_client_config["id"];
    client_config["_key"] = new_client_config["_key"];
    client_config["algorithm"] = new_client_config["algorithm"] or "sha256";

    local parsed_base = url.parse(new_client_config["base_url"])
    computed_client_config["host"] = parsed_base["host"]
    computed_client_config["port"] = get_port(parsed_base)

    if parsed_base["scheme"] == "https" then
        client_config["requestor"] = https
    else
        client_config["requestor"] = http
    end
end


-- private function for making hawk-signed HTTP requests
local function json_request(method, uri, body)
    local body_json = ""
    if body then
        body_json = body
    end

    local headers = {
        Authorization = hawk_header(
            client_config,
            {
                method = method,
                host = computed_client_config["host"],
                port = computed_client_config["port"],
                resource = uri,
            },
            {
                payload = body_json,
                content_type = "application/json"
            }),
        Host = string.format("%s:%s", computed_client_config["host"], computed_client_config["port"]),
        ["Content-Type"] = "application/json",
        ["Content-Length"] = #body_json,
    }

    local response = {}
    local r, code, resp_headers = client_config["requestor"].request {
        method = method,
        url = string.format("%s%s", client_config.base_url, uri),
        headers = headers,
        source = ltn12.source.string(body_json),
        sink = ltn12.sink.table(response)
    }

    return {
        r = r,
        status_code = code,
        body = table.concat(response),
        headers = resp_headers,
    }
end

configure_client(client_cfg)

function process_message()
    violations = read_message("Fields[violations]")
    json_request("PUT", "/violations/", violations)
    return 0
end

function timer_event(ns)
    -- no op
end

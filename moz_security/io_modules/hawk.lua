-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Hawk Request Module

The hawk request module can be used to generate a Hawk header suitable for
inclusion in a request to a web server that requires Hawk authentication.

https://github.com/hueniverse/hawk

## Functions

### new

Return a new header generator that can be called repeatedly to generate hawk
headers to include in a request. get_header can be called on the returned
table.

```lua
local hawk = require "hawk"

local hdrgen = hawk.new("myuser", "mykey", "web.host", 443)
myhdr = hdrgen:get_header("PUT", "/uri/path", "{}", "application/json")
```

*Arguments*
- id (string) - Hawk ID
- key (string) - Hawk secret
- host (string) - The hostname requests will be made to
- port (number) - The port requests will be made on

*Return*
- hdrgen (table) - Header generator with callable get_header function

### hdrgen:get_header

Return a string usable as a Hawk header in a request.

*Arguments*
- method (string) - HTTP request method
- uri (string) - URI (path) for request
- payload (string) - Body of request, or nil if no body
- content-type (string) - Content type, or nil if no body

*Return*
- header (string) - Generated Hawk header

--]]

local string    = require("string")
local table     = require("table")
local digest    = require("openssl").digest
local hmac      = require("openssl").hmac
local random    = require("openssl").random
local mime      = require("mime")
local os        = require("os")

local setmetatable = setmetatable
local type         = type
local error        = error

local M = {}
setfenv(1, M)

local hawk = {}
hawk.__index = hawk


local function url_escape(s)
    return s:gsub("+", "-"):gsub("/", "_"):gsub("=", "")
end


local function nonce(size)
    return url_escape(mime.b64(random(size)))
end


local function hash_payload(payload, algorithm, content_type)
    local normalized = "hawk.1.payload"
    normalized = string.format("%s\n%s", normalized, string.lower(content_type))
    normalized = string.format("%s\n%s\n", normalized, payload)
    return mime.b64(digest.digest(algorithm, normalized, true))
end


local function normalize_string(artifacts)
    local h = ""
    if artifacts.hash then h = artifacts.hash end
    local normalized = {
        "hawk.1.header",
        artifacts.ts,
        artifacts.nonce,
        string.upper(artifacts.method),
        artifacts.resource,
        string.lower(artifacts.host),
        artifacts.port,
        h,
        "",
    }
    return string.format("%s\n", table.concat(normalized, "\n"))
end


local function calculate_mac(key, artifacts)
    return mime.b64(hmac.hmac("sha256", normalize_string(artifacts), key, true))
end


local function hawk_header(id, key, artifacts, options)
    if options.payload and options.content_type then
        artifacts.hash = hash_payload(options.payload, "sha256", options.content_type)
    end

    local mac = calculate_mac(key, artifacts)
    local header = string.format("Hawk id=\"%s\", ts=\"%s\", nonce=\"%s\"",
        id, artifacts.ts, artifacts.nonce)

    if artifacts.hash then
        header = string.format("%s, hash=\"%s\"", header, artifacts.hash)
    end

    return string.format("%s, mac=\"%s\"", header, mac)
end


function hawk:get_header(method, uri, body, content_type)
    local artifacts = {
        method = method,
        host = self.host,
        port = self.port,
        resource = uri,
        ts = os.time(),
        nonce = nonce(6)
    }
    local options = {}
    if body then
        options.payload = body
        options.content_type = content_type
    end
    return hawk_header(self.id, self.key, artifacts, options)
end


function new(id, key, host, port)
    self = setmetatable({}, hawk)

    -- Do some verification of the supplied parameters here, it's possible we wont know
    -- a bad parameter was specified until we try to generate a header later
    if type(id) ~= "string" then
        error("invalid id parameter")
    end
    if type(key) ~= "string" then
        error("invalid key parameter")
    end
    if type(host) ~= "string" or string.find(host, "/") then
        -- Make sure the host parameter is only the hostname and does not contain URL parameters
        error("invalid host or host contains request path characters")
    end
    if type(port) ~= "number" then
        error("invalid port parameter")
    end

    self.id = id
    self.key = key
    self.host = host
    self.port = port
    return self
end

return M

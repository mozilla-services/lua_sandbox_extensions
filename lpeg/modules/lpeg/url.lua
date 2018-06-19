-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# URL Module

The URL LPEG module provides basic grammars for parsing URL strings. This
includes base URL strings in addition to request strings with an HTTP method
and protocol.

This module is specifically designed for use in analysis sandboxes. For
input/output modules, the functions in socket.url may be more appropriate.

## Variables

### LPEG Grammars

* `url`      - Process a URL, e.g., http://example.host/request?arg=value
* `urlparam` - Given the path component of a url, return URL decoded parameters
* `request`  - Basic parsing of a request string, e.g., GET http://example.host HTTP/1.1
--]]

local l         = require "lpeg"
local string    = require "string"
local rawset    = rawset
local tonumber  = tonumber

l.locale(l)

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local function urldecode(s)
    local h = function(x)
        return string.char(tonumber(x, 16))
    end

    s = string.gsub(s, "+", " ")
    s = string.gsub(s, "%%(%x%x)", h)
    return s
end

local function urlnos(x, ignore)
    if ignore then return (1 - l.P(x))^1 * l.P(x)^0 end
    return l.Cs((1 - l.P(x))^1 / urldecode) * l.P(x)^0
end

local paramvalue = l.Cg(urlnos("=") * urlnos("&"))

urlparam = urlnos("?", true) * l.Cf(l.Ct("") * paramvalue^0, rawset)

local scheme        = l.Cg(l.alnum^1, "scheme") * l.P("://")
local hostname      = l.Cg((1 - (l.space + l.S("/?:")))^1, "hostname")
local path          = l.Cg((1 - l.space)^1, "path")^-1
local port          = (l.P(":") * l.Cg(l.digit^1, "port"))^-1
local userinfo      = (l.Cg((1 - l.P(":"))^1 * l.P(":") * (1 - l.P("@"))^1, "userinfo") * l.P("@"))^-1
local urlcomp       = (scheme * userinfo * hostname * port)^-1 * path

url = l.Ct(urlcomp)

local method        = l.Cg((1 - l.space)^1, "method")
local protocol      = l.Cg((1 - l.space)^1, "protocol")^-1

request = l.Ct(method * l.space * urlcomp * l.space^-1 * protocol)

return M

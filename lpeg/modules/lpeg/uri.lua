-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# URI RFC 3986 Module

## Variables
### LPEG Grammars
* uri - RFC3986 URI
* uri_reference - full or relative (e.g., "test.html?foo=bar") URI references
* url_query - parses a URL query string into a hash (duplicate keys are overwritten)
--]]

-- Imports
local l = require "lpeg"
l.locale(l)
local es  = require "lpeg.escape_sequences"
local ipa = require "lpeg.ip_address"

local rawset = rawset

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local unreserved    = l.alnum + l.S"-._~"
local pct_encoded   = l.P"%" * l.xdigit * l.xdigit
local sub_delims    = l.S"!$&'()*+,;="
local ipvfuture     = l.P"v" * l.xdigit^1 * "." * (unreserved + sub_delims + ":")^1
local ip_literal    = l.P"[" * l.C(ipa.v6 + ipvfuture) * l.P"]"
local host          = l.Cg(ip_literal + ipa.v4 + ipa.hostname, "host")
local port          = l.Cg(l.digit^0, "port")
local scheme        = l.Cg(l.alpha * (l.alpha + l.digit + l.S"+-.")^0, "scheme")
local userinfo      = l.Cg(l.Cs((unreserved + es.percent + sub_delims + ":")^0), "userinfo")
local authority     = (userinfo * "@")^-1 * host * (l.P":" * port)^-1
local pchar         = unreserved + es.percent + sub_delims + l.S":@"
local qchar         = unreserved + pct_encoded + sub_delims + l.S":@"
local segment       = pchar^0
local segment_nz    = pchar^1
local segment_nz_nc = (unreserved + es.percent + sub_delims + "@")^1
local path_abempty  = l.Cg(l.Cs((l.P"/" * segment)^0), "path")
local path_absolute = l.Cg(l.Cs(l.P"/" * (segment_nz * (l.P"/" * segment)^0)^-1), "path")
local path_noscheme = l.Cg(l.Cs(segment_nz_nc * (l.P"/" * segment)^0), "path")
local path_rootless = l.Cg(l.Cs(segment_nz * (l.P"/" * segment)^0), "path")
local path_empty    = -pchar
local query         = l.P"?" * l.Cg((qchar + l.S"/?")^0, "query")
local fragment      = l.P"#" * l.Cg((pchar + l.S"/?")^0, "fragment")
local hier_part     = l.P"//" * authority * path_abempty
    + path_absolute
    + path_rootless
    + path_empty

local relative_part = l.P"//" * authority * path_abempty
    + path_absolute
    + path_noscheme
    + path_empty

local full_ref      = scheme * ":" * hier_part * query^-1 * fragment^-1
local relative_ref  = relative_part * query^-1 * fragment^-1

uri             = l.Ct(full_ref * l.P(-1))
uri_reference   = l.Ct((full_ref + relative_ref) * l.P(-1))

local qkend     = l.S"=&" -- allow standalone keys e.g., ?foo -> foo = ""
local qvend     = l.S"&"
local qkey      = l.Cs(((es.url + 1) - qkend)^1)
local qvalue    = l.Cs(((es.url + 1) - qvend)^0) * qvend^0
local qfield    = qkey * ((l.P"=" * qvalue) + (qvend^0 * l.Cc""))
url_query       = l.Cf(l.Ct("") * l.Cg(qfield)^0, rawset) * l.P(-1)

return M

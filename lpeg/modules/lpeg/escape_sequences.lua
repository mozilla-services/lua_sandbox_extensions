-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Escape Sequence Module

## Variables
### LPEG Grammars
* `c` - matches and converts C/C++ escape sequences
* `json` - matches and converts JSON escape sequences
* `percent` - matches and converts URI percent escape sequences
* `url` - matches and converts URL escape sequences (plus and percent)

## Functions

### hex_to_utf8

Converts a hex string into a UTF-8 string

*Arguments*
- s (string) - e.g. "OO41" -> "A"

*Return*
- string UTF-8 byte sequence


### hex_to_char

Converts a hexadecimal string into a single character string

*Arguments*
- s (string) - e.g. "28" -> "("

*Return*
- string


### octal_to_char

Converts an octal string into a single character string

*Arguments*
- s (string) - e.g. "50" -> "("

*Return*
- string
--]]

-- Imports
local math      = require "math"
local string    = require "string"
local l         = require "lpeg"
l.locale(l)

local tonumber  = tonumber

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local esc_prefix    = l.P"\\"
local hex2          = l.xdigit * l.xdigit
local hex4          = l.xdigit * l.xdigit * l.xdigit * l.xdigit
local u16           = l.P"u"
local u32           = l.P"U"
local hex           = l.P"x"
local octal         = l.R"07"

local c_char_set = l.S"abefnrtv\\'\"?"
local c_char_lookup = {
    a = "\a",
    b = "\b",
    e = "\27",
    f = "\f",
    n = "\n",
    r = "\r",
    t = "\t",
    v = "\v",
    ["\\"] = "\\",
    ["'"] = "'",
    ['"'] = '"',
    ["?"] = "?"
}


local json_char_set = l.S"bfnrt/\\\""
local json_char_lookup = {
    b = "\b",
    f = "\f",
    n = "\n",
    r = "\r",
    t = "\t",
    ["/"] = "/",
    ["\\"] = "\\",
    ['"'] = '"',
}


function hex_to_utf8(s)
    local v = tonumber(s, 16)
    if v <= 0x007f then
        return string.char(v)
    elseif v <= 0x07ff then
        local h = math.floor((v / 64) % 64)
        local c0 = 192 + h
        local c1 = 128 + (v - h * 64)
        return string.char(c0, c1)
        -- return string.format("%02x %02x", c0, c1)
    elseif v <= 0xffff then
        local h = math.floor((v / 4096) % 4096)
        local c0 = 224 + h
        v = v - h * 4096
        h = math.floor((v / 64) % 64)
        local c1 = 128 + h
        local c2 = 128 + (v - h * 64)
        return string.char(c0, c1, c2)
        -- return string.format("%02x %02x %02x", c0, c1, c2)
    elseif v <= 0x10ffff then
        local h = math.floor((v / 262144) % 262144)
        local c0 = 240 + h
        v = v - h * 262144
        h = math.floor((v / 4096) % 4096)
        local c1 = 128 + h
        v = v - h * 4096
        h = math.floor((v / 64) % 64)
        local c2 = 128 + h
        local c3 = 128 + (v - h * 64)
        return string.char(c0, c1, c2, c3)
        -- return string.format("%02x %02x %02x %02x", c0, c1, c2, c3)
    else
        return string.char(239, 191, 189)
    end
end


function hex_to_char(s)
    return string.char(tonumber(s, 16))
end


function octal_to_char(s)
    return string.char(tonumber(s, 8))
end


c = l.Cg(esc_prefix * (
    c_char_set / c_char_lookup
    + u16 * (hex4 / hex_to_utf8)
    + u32 * (hex4 * hex4 / hex_to_utf8)
    + hex * (l.xdigit * l.xdigit^-1 / hex_to_char) -- technically should be ^0
    + octal * octal^-2 / octal_to_char
    ))


json = l.Cg(esc_prefix * (
    json_char_set / json_char_lookup
    + u16 * (hex4 / hex_to_utf8)
    ))

percent = l.Cg(l.P"%" * (l.xdigit * l.xdigit / hex_to_char))

url = l.P"+" / " " + percent

return M

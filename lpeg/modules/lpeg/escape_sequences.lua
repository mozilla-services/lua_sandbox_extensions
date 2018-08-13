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

### escape_html

Defensively escapes HTML strings

*Arguments*
- s (string) - e.g. "&" -> "&amp;"

*Return*
- string


### escape_json

Standard JSON escaping

*Arguments*
- s (string) - e.g. "\t" -> "\\t"

*Return*
- string


### escape_url

Standard URL escaping

*Arguments*
- s (string) - e.g. " " -> "%20"

*Return*
- string
--]]

-- Imports
local math      = require "math"
local string    = require "string"
local l         = require "lpeg"
l.locale(l)

local tonumber  = tonumber
local tostring  = tostring

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


local escape_json_lookup = {
    ["\\"] = "\\\\",
    ['"'] = '\\"',
    ["/"] = "\\/",
    ["\00"] = "\\u0000",
    ["\01"] = "\\u0001",
    ["\02"] = "\\u0002",
    ["\03"] = "\\u0003",
    ["\04"] = "\\u0004",
    ["\05"] = "\\u0005",
    ["\06"] = "\\u0006",
    ["\07"] = "\\u0007",
    ["\08"] = "\\b",
    ["\09"] = "\\t",
    ["\10"] = "\\n",
    ["\11"] = "\\u000B",
    ["\12"] = "\\f",
    ["\13"] = "\\r",
    ["\14"] = "\\u000E",
    ["\15"] = "\\u000F",
    ["\16"] = "\\u0010",
    ["\17"] = "\\u0011",
    ["\18"] = "\\u0012",
    ["\19"] = "\\u0013",
    ["\20"] = "\\u0014",
    ["\21"] = "\\u0015",
    ["\22"] = "\\u0016",
    ["\23"] = "\\u0017",
    ["\24"] = "\\u0018",
    ["\25"] = "\\u0019",
    ["\26"] = "\\u001A",
    ["\27"] = "\\u001B",
    ["\28"] = "\\u001C",
    ["\29"] = "\\u001D",
    ["\30"] = "\\u001E",
    ["\31"] = "\\u001F"
}
function escape_json(s)
    return string.gsub(tostring(s), '[%z\1-\31\\"/]', escape_json_lookup)
end


local escape_html_lookup = {
    ["\00"] = "&#0;",
    ["\01"] = "&#1;",
    ["\02"] = "&#2;",
    ["\03"] = "&#3;",
    ["\04"] = "&#4;",
    ["\05"] = "&#5;",
    ["\06"] = "&#6;",
    ["\07"] = "&#7;",
    ["\08"] = "&#8;",
    ["\09"] = "&#9;",
    ["\10"] = "&#10;",
    ["\11"] = "&#11;",
    ["\12"] = "&#12;",
    ["\13"] = "&#13;",
    ["\14"] = "&#14;",
    ["\15"] = "&#15;",
    ["\16"] = "&#16;",
    ["\17"] = "&#17;",
    ["\18"] = "&#18;",
    ["\19"] = "&#19;",
    ["\20"] = "&#20;",
    ["\21"] = "&#21;",
    ["\22"] = "&#22;",
    ["\23"] = "&#23;",
    ["\24"] = "&#24;",
    ["\25"] = "&#25;",
    ["\26"] = "&#26;",
    ["\27"] = "&#27;",
    ["\28"] = "&#28;",
    ["\29"] = "&#29;",
    ["\30"] = "&#30;",
    ["\31"] = "&#31;",
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;",
    ['"'] = "&quot;",
    ["'"] = "&apos;",
    ["`"] = "&grave;",
    ["!"] = "&excl;",
    ["@"] = "&copy;",
    ["$"] = "&dollar;",
    ["%"] = "&percnt;",
    ["("] = "&lpar;",
    [")"] = "&rpar;",
    ["="] = "&equals;",
    ["+"] = "&plus;",
    ["{"] = "&lcub;",
    ["}"] = "&rcub;",
    ["["] = "&lsqb;",
    ["]"] = "&rsqb;"
}
function escape_html(s)
    return string.gsub(tostring(s), "[%z\1-\31&<>\"'`!@$%%()=+{}[%]]", escape_html_lookup)
end


local function escape_url_fn(s)
    return string.format("%%%02x", string.byte(s))
end


function escape_url(s)
    return string.gsub(tostring(s), "[^-_.~a-zA-Z0-9]", escape_url_fn)
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

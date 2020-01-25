-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# printf Parser Module

See: http://www.cplusplus.com/reference/cstdio/printf/

## Variables
- none

## Functions

### build_grammar

Constructs an LPEG grammar based on the printf format/args array.

*Arguments*
- t (array) - Column one is the format string and the additional columns are the
  capture names of the arguments. Capture names starting with an `@` are lpeg.re
  expressions so the default parser for a type can be overridden when necessary.

*Return*
- grammar (LPEG user data object) or an error is thrown

### load_messages

Compile the provide list of printf_messages into the grammars table.

*Arguments*
- printf_messages (array) - array of printf message specifications to be compiled into grammars
```lua
printf_messages = {
 -- array (string and/or array) the order specified here is the load and evaluation order.
   -- string: name of a module containing a `printf_messages` array to import
   -- array: creates an on the fly grammar using a printf format specifications.
     -- see: https://mozilla-services.github.io/lua_sandbox_extensions/lpeg/modules/lpeg/printf.html

 {"%s:%lu: invalid line", "path", "linenum"},
 "lpeg.openssh_portable", -- must export a `printf_messages` array
}
```
- grammars (array/nil) - optional existing grammar array to append to
- grammars_size (number/nil) - number of items in the array
- module (string/nil) - identifer to help locate errors in nested includes

*Return*
- grammars (array) or an error is thrown


### match_sample

Finds the grammar associated with the specified log message.

*Arguments*
- grammars (array) - Output from load_printf_grammars

*Return*
- grammar (userdata/nil) - Best match for the sample input or nil if no match is found
--]]

-- Imports
local string    = require "string"
local l         = require "lpeg"
l.locale(l)
local es        = require "lpeg.escape_sequences"
local re        = require "re"

local ipairs    = ipairs
local error     = error
local pcall     = pcall
local require   = require
local type      = type
local tonumber  = tonumber

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local flags         = l.Cg((l.S"-+ #0")^0, "flags")
local width         = l.Cg(l.digit^1 + "*", "width")
local precision     = l.P"." * l.Cg(l.digit^0 + l.P"*" + l.Cc"0", "precision")
local length        = l.Cg(l.P"hh" + "h" + "ll" + "l" + "j" + "z" + "t" + "L", "length")
local specifier     = l.Cg(l.S"diuoxXfFeEgGaAcspn%", "specifier")
local format        = l.Ct(l.P"%" * flags^-1 * width^-1 * precision^-1 * length^-1 * specifier)
local literal_c     = 1 - l.S"%\\"
local literal       = l.Cs((literal_c + es.c + l.P"%%"/"%%")^1)
local segment       = literal + format
local fmt_string    = l.Ct(segment * segment^0)

local sign      = l.S"+-"
local decimal   = l.P"." * l.digit^0
local exponent  = l.S"eE" * sign^-1 * l.digit^1
local float     = sign^-1 * l.digit^1 * decimal^-1 * exponent^-1
local hdecimal  = l.P"." * l.xdigit^0
local hexponent = l.S"pP" * sign^-1 * l.digit^1
local hfloat    = sign^-1 * l.P"0" * l.S"xX" * l.xdigit^1 * hdecimal^-1 * hexponent^-1
local sp        = l.P" "


local width_functions = {} -- cache of width functions to reuse
local function get_width_function(w)
    w = tonumber(w)
    local fn = width_functions[w]
    if fn then return fn end

    fn = function(s, cpos, spos, val)
        local len = cpos - spos
        if len < w then cpos = cpos + w - len end
        return cpos, val
    end
    width_functions[w] = fn
    return fn
end


local function add_padding(t, grammar)
    local prefix
    if not t.specifier:match("[csp]") and t.flags:match(" ") then
        prefix = sp
    end

    if not t.flags:match("-") and t.width then -- right justified
        local tmp = sp^0
        if prefix then
            prefix = prefix * tmp
        else
            prefix = tmp
        end
    end

    if prefix then
        grammar = prefix * grammar
    end

    if t.flags:match("-") and t.width then -- left justified
        if t.width == "*" then
            -- this has to make a number of assumptions
            -- * the output is less than the provided width
            -- * the next field or literal doesn't start with a space
            grammar = grammar * sp^0
        else
            local fn = get_width_function(t.width)
            grammar = l.Cmt(l.Cp() * grammar, fn)
        end
    end
    return grammar
end


local function hex_to_number(v)
    return tonumber(v, 16)
end


local function octal_to_number(v)
    return tonumber(v, 8)
end


local trim_grammar = sp^0 * l.C((sp^0 * (1 - sp)^1)^0)
local function trim(s)
    return trim_grammar:match(s)
end


local function get_type_grammar(t)
    local padding_needed = true
    local grammar
    if t.specifier:match("[di]") then
        grammar = (sign^-1 * l.digit^0) / tonumber
    elseif t.specifier:match("u") then
        grammar = l.digit^0 / tonumber
    elseif t.specifier == "o"  then
        grammar = l.R"07"^0 / octal_to_number
    elseif t.specifier:match("[fFeEgG]") then
        grammar = float / tonumber
    elseif t.specifier:match("[xX]") then
        grammar = (l.P"0" * l.S"xX")^-1 * (l.xdigit^0 / hex_to_number)
    elseif t.specifier:match("[aA]") then
        grammar = hfloat / tonumber
    elseif t.specifier == "c" then
        grammar = l.C(l.P(1))
    elseif t.specifier == "s" then
        if t.precision and t.precision ~= "*" then
            local p = tonumber(t.precision)
            local max_len = p
            if t.width and t.width ~= "*" then
                local w = tonumber(t.width)
                if w > max_len then
                    max_len = w
                end
                grammar = l.P(1)^-max_len / trim
                padding_needed = false
            else
                -- the best we can do here is assume a space delimiter
                grammar = l.C((l.P(1) - sp)^-max_len)
                end
        else
            grammar = l.C((l.P(1) - sp)^0)
        end
    elseif t.specifier == "p" then
        grammar = l.C(l.P"0x" * l.xdigit^1)
    else
        grammar = l.P"" -- ignored e.g. %n
    end
    if padding_needed then
        return add_padding(t, grammar)
    end
    return grammar
end


local function get_literal_grammar(t, v, i)
    local lit = l.P(v)
    if t[i + 1] == nil then lit = lit * l.space^0 * l.P(-1) end
    return lit
end


function build_grammar(fmt_table)
    local fmt = fmt_table[1]
    if type(fmt) ~= "string" then
        error("printf format must be a string", 0)
    end

    local t = fmt_string:match(fmt)
    if not t then error("could not parse the printf format string: " .. fmt, 0) end

    local gt = {}
    local arg = 2
    local len = #t
    local i = 1
    while i <= len do
        local v = t[i]
        local typ = type(v)
        if typ == "string" then
            gt[i] = get_literal_grammar(t, v, i)
        elseif typ == "table" then
            if v.width == "*" then arg = arg + 1 end
            local cn = fmt_table[arg]
            local cntyp = type(cn)
            if cntyp == "userdata" then
                gt[i] = cn
            elseif cntyp == "string" then
                local ni = i + 1
                local nv = t[ni]
                local exp = string.match(cn, "^@(.+)")
                if exp then
                    local ok, g = pcall(re.compile, exp)
                    if not ok then
                        error(string.format("fmt: '%s' arg: %d error: '%s'",
                                            fmt, arg - 1, g), 0)
                    end
                    gt[i] = g
                elseif v.specifier == "s" and v.precision and v.precision ~= "*" then
                    gt[i] = l.Cg(get_type_grammar(v), cn)
                elseif v.specifier == "s" and nv == nil then
                        gt[i] = l.Cg(trim_grammar, cn)
                elseif v.specifier == "s" and type(nv) == "string"  then
                    -- use the next literal to mark the end of this string
                    local lit = get_literal_grammar(t, nv, ni)
                    gt[i] = l.Cg(add_padding(v, l.C((l.P(1) - lit)^0)), cn)
                    gt[ni] = lit
                    i = ni
                else
                    gt[i] = l.Cg(get_type_grammar(v), cn)
                end
            else
                error(string.format("fmt: '%s' arg: %d error: 'invalid type'",
                                    fmt, arg - 1), 0)
            end
            arg = arg + 1
        end
        i = i + 1
    end

    local grammar = gt[1]
    for i=2, #gt do
        grammar = grammar * gt[i]
    end
    return l.Ct(grammar * l.space^0 * l.P(-1))
end


function load_messages(printf_messages, grammars, grammars_size, mod)
    if not grammars then grammars = {} end
    if not grammars_size then grammars_size = #grammars end
    if not mod then mod = "<root>" end

    for i,v in ipairs(printf_messages) do
        if type(v) == "table" then
            grammars_size = grammars_size + 1
            local ok, g = pcall(build_grammar, v)
            if not ok then
                error(string.format("module: %s item: %d error: %s", mod, i, g), 0)
            end
            grammars[grammars_size] = {g, #v} -- column 2 is the weight
        else
            local m = require(v)
            if type(m.printf_messages) == "table" then
                load_messages(m.printf_messages, grammars, grammars_size, v)
            else
                error(string.format("module: %s does not contain a 'printf_messages' array", v), 0)
            end
        end
    end
    return grammars
end


function match_sample(grammars, sample)
    local weight = 0
    local best_match
    for i,v in ipairs(grammars) do
        if v[1]:match(sample) then
            if v[2] > weight then
                best_match = v[1]
                weight = v[2]
            end
        end
    end
    return best_match
end

return M

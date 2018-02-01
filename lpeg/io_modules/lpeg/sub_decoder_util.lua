-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Sub Decoder Utility Module

Common funtionality to instantiate an LPeg based sub decoder configuration.

## Functions

### load_sub_decoders

Returns a table of sub_decoder functions, keyed by sub_decoder_name.

*Arguments*
- sub_decoders (table) sub_decoders configuration table
```lua
sub_decoders = {
-- sub_decoder_name (string) = (string/array) a sub_decoder_name of "*" is
-- treated as the default when the name does not exist.
  -- string: decoder or grammar module name
  -- array: (string and/or array) list of specific messages to parse
    -- string: Sample message used to locate the correct grammar
       -- If no grammar matches the sample message then an error is thrown
       -- and another grammar or module must be added to the printf_messages
       -- configuration. If multiple grammars match the message, the first
       -- grammar with the most specific match is selected.
       -- Note: a special token of `<<DROP>>` and `<<FAIL>>` are reserved for
       -- the last entry in the array to handle the no match case; <<DROP>>
       -- silently discards the message and <<FAIL>> reports an error. If
       -- neither is specified the default no match behavior is to inject the
       -- original message produced by the syslog decoder.
    -- array:
       -- column 1: (string/array)
          -- string: Sample message (see above)
          -- array: printf.build_grammar format specification
       -- column 2: (table/nil)
          -- Transformation table with Heka message field name keys and a
          -- value of the fully qualified transformation function name. The
          -- function returns no values but can error; it receives two
          -- arguments: the Heka message table and the field name to act on.
          -- The function can modify the message in any way.

  nginx  = "decoders.nginx.access", -- decoder module name
  kernel = "lpeg.linux.kernel",     -- grammar module name, must export an lpeg grammar named 'grammar' or 'syslog_grammar'
  sshd = {
    -- openssh_portable auth message, imported in printf_messages
    {"Accepted publickey for foobar from 10.11.12.13 port 4242 ssh2", {remote_addr = "geoip.heka.add_geoip"}},
  },
  foo = {
    "/tmp/input.tsv:23: invalid line", -- custom log defined in printf_messages
    {{"Status: %s", "status"}, nil},   -- inline printf spec, no transformation
  },
}
```
- printf_messages (table/nil) see: https://mozilla-services.github.io/lua_sandbox_extensions/lpeg/modules/lpeg/printf.html

*Return*
- sub_decoders (table)

### load_sub_decoder

Returns the decode function for a single sub_decoder.

*Arguments*
- sub_decoder (string/table) sub_decoder configuration entry
```lua
sub_decoder = "decoders.nginx.access"
```
- printf_messages (table/nil) printf_message table (see above)

*Return*
- decode (function)

### copy_message

Copies a message for use in decoder/subdecoder

*Arguments*
* src (table) Heka message table. This is a shallow copy of the individual
  values in the Fields hash and assumes they will be replaced as opposed to
  modified when they are tables. The main use of this function is to populate
  a new message with defaults.
* mutable (bool/nil/none)

*Return*
* msg (table) a Heka message hash schema format

### add_fields

Add the fields hash to the msg.Fields overwriting on collision.

*Arguments*
* msg (table) Heka message
* fields (table) Heka message Fields hash

*Return*
* none - msg is modified in place

--]]

-- Imports
local string    = require "string"
local printf    = require "lpeg.printf"

local error         = error
local ipairs        = ipairs
local pairs         = pairs
local require       = require
local setmetatable  = setmetatable
local type          = type

local inject_message    = inject_message

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local FAIL_TOKEN = "<<FAIL>>"
local DROP_TOKEN = "<<DROP>>"

local function grammar_decode_fn(g)
    return function(data, dh, mutable)
        local fields = g:match(data)
        if not fields then return "parse failed" end
        local msg = copy_message(dh, mutable)
        add_fields(msg, fields)
        inject_message(msg)
    end
end


local function grammar_pick_fn(sd, nomatch_action)
    return function(data, dh, mutable)
        local msg = dh
        local fields
        for _,cpg in ipairs(sd) do  -- individually check each grammar
            fields = cpg[1]:match(data)
            if fields then
                msg = copy_message(dh, mutable)
                add_fields(msg, fields)
                if cpg[2] then -- apply user defined transformation functions
                    for k,f in pairs(cpg[2]) do
                        f(msg, k)
                    end
                end
                break
            end
        end
        if not fields and nomatch_action then
            if nomatch_action == DROP_TOKEN then
                return
            elseif nomatch_action == FAIL_TOKEN then
                return "parse failed"
            end
        end
        inject_message(msg)
    end
end


local function load_sub_decoder_impl(sd, grammars, sdk)
    local sdt = type(sd)
    if sdt == "string" then
        if sd:match("^decoders%.") then
            local decode = require(sd).decode
            if type(decode) ~= "function"  then
                error(string.format("sub_decoder, no decode function defined: %s", sdk))
            end
            return decode
        else
            local m = require(sd)
            local g = m.grammar or m.syslog_grammar
            if type(g) ~= "userdata" then
                error(string.format("sub_decoder, no grammar defined: %s", sdk))
            end
            return grammar_decode_fn(g)
        end
    elseif sdt == "table" then -- cherry pick printf grammars
        local nomatch_action
        for i,cpg in ipairs(sd) do
            if type(cpg) ~= "table" then
                cpg = {cpg}
                sd[i] = cpg
            end

            local g
            local typ = type(cpg[1])
            if typ == "string" then
                if (cpg[1] == DROP_TOKEN or cpg[1] == FAIL_TOKEN) and sd[i + 1] == nil then
                    nomatch_action = cpg[1]
                    sd[i] = nil
                    break
                end
                g = printf.match_sample(grammars, cpg[1])
                if not g then
                    error(string.format("no grammar found for: %s", cpg[1]))
                end
            elseif typ == "table" then
                g = printf.build_grammar(cpg[1])
            else
                error(string.format("sub_decoder: %s invalid entry: %d", sdk, i))
            end
            cpg[1] = g

            if cpg[2] then
                for k,v in pairs(cpg[2]) do
                    local fn
                    local mname, fname = string.match(v, "(.-)%.([^.]+)$")
                    if mname then
                        fn = require(mname)[fname]
                    else
                        fn = _G[cpg[2]]
                    end
                    if type(fn) ~= "function" then
                        error(string.format("invalid transformation function %s=%s", k, v))
                    end
                    cpg[2][k] = fn
                end
            end
        end
        return grammar_pick_fn(sd, nomatch_action)
    else
        error(string.format("sub_decoder: %s invalid type: %s", sdk, sdt))
    end
end


function load_sub_decoder(sd, pfm)
    local grammars = printf.load_messages(pfm or {})
    return load_sub_decoder_impl(sd, grammars, "")
end


function load_sub_decoders(sds, pfm)
    local sub_decoders  = {}
    local grammars = printf.load_messages(pfm or {})

    for sdk,sd in pairs(sds or {}) do
        if sdk == "*" then
            local fn = load_sub_decoder_impl(sd, grammars, sdk)
            local mt = {__index = function(t, k) return fn end }
            setmetatable(sub_decoders, mt);
        else
            sub_decoders[sdk] = load_sub_decoder_impl(sd, grammars, sdk)
        end
    end
    return sub_decoders
end


function copy_message(msg, mutable)
    if msg and not mutable then
        local t = {
            Uuid        = msg.Uuid,
            Logger      = msg.Logger,
            Hostname    = msg.Hostname,
            Timestamp   = msg.Timestamp,
            Type        = msg.Type,
            Payload     = msg.Payload,
            EnvVersion  = msg.EnvVersion,
            Pid         = msg.Pid,
            Severity    = msg.Severity
        }
        if type(msg.Fields) == "table" then
            local f = {}
            t.Fields = f
            for k,v in pairs(msg.Fields) do
                f[k] = v
            end
        end
        return t
    end
    return msg or {}
end


function add_fields(msg, fields)
    if msg.Fields then
        for k,v in pairs(fields) do
            msg.Fields[k] = v
        end
    else
        msg.Fields = fields
    end
end

return M

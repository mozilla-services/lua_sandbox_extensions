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
- sub_decoders (table/nil) sub_decoders configuration table
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
       -- original message produced by the parent decoder.
    -- array:
       -- column 1: (string/array)
          -- string: Sample message (see above) or a decoder module specification
            -- A decoder module specification is used when transformations need
            -- to be applied to a standard decoder output.
              -- Caveats:
              -- 1) the decoder output must be a Lua Heka message table
              -- 2) this must be the only entry in the configuration array
              -- 3) printf_messages must not be defined
          -- array:
            -- printf.build_grammar format specification
            -- module reference to a grammar builder function, any additional columns are passed to the function
            -- module reference to a an LPeg grammar, any additional columns are passed to match see [Carg](http://www.inf.puc-rio.br/~roberto/lpeg/#cap-arg)
       -- column 2: (table/nil)
          -- Transformation table with Heka message field name keys and a
          -- value of the fully qualified transformation function name
          -- `<module_name>#<function_name>`. The function returns no values but
          -- can error; it receives two arguments: the Heka message table and
          -- the field name to act on. The function can modify the message in
          -- any way.

  nginx  = "decoders.nginx.access", -- decoder module name
  kernel = "lpeg.linux.kernel",     -- grammar module name, must export an lpeg grammar named 'grammar' or 'syslog_grammar'
  -- kernel = "lpeg.linux.kernel#syslog_grammar", -- the above is a shorthand for the explicit grammar specification
  sshd = {
    -- openssh_portable auth message, imported in printf_messages
    {"Accepted publickey for foobar from 10.11.12.13 port 4242 ssh2", {remote_addr = "geoip.heka#add_geoip"}},
  },
  foo = {
    "/tmp/input.tsv:23: invalid line", -- custom log defined in printf_messages
    { {"Status: %s", "status"}, nil},  -- inline printf spec, no transformation
    { {"example#fn", arg1}, nil},      -- use fn(arg1) from the example module to build a grammar
    { {"example#foo"}, nil},           -- use the foo LPeg grammar from the example module
  },
}
```
- printf_messages (table/nil) see: https://mozilla-services.github.io/lua_sandbox_extensions/lpeg/modules/lpeg/printf.html

*Return*
- sub_decoders (table)

### load_decoder

Returns the decode function for a single decoder. `load_sub_decoder` is an alias
to this function and has been kept for backwards compatibility.

*Arguments*
- decoder (string/table) decoder configuration entry
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
local next          = next
local pairs         = pairs
local require       = require
local setmetatable  = setmetatable
local type          = type
local unpack        = unpack

local real_inject_message = inject_message
local function interpose_inject_message(im)
    inject_message = im
end

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local FAIL_TOKEN = "<<FAIL>>"
local DROP_TOKEN = "<<DROP>>"

local function grammar_decode_fn(g)
    return function(data, dh, mutable)
        -- the grammar is expected to return a table compatible with the hash
        -- based Heka message Fields entry
        -- http://mozilla-services.github.io/lua_sandbox/heka/message.html#Hash_Based_Message_Fields
        local fields = g:match(data)
        if not fields then return "parse failed" end
        local msg = copy_message(dh, mutable)
        add_fields(msg, fields)
        real_inject_message(msg)
    end
end


local function grammar_fn(g)
    return function(data)
        return g:match(data)
    end
end


local function grammar_fn_args(g, args)
    return function(data)
        return g:match(data, 1, unpack(args, 2))
    end
end


local function grammar_pick_fn(sd, nomatch_action)
    return function(data, dh, mutable)
        local msg = copy_message(dh, mutable)
        msg.Payload = data -- keep the original, the context is needed in most cases
        local fields
        for _,cpg in ipairs(sd) do  -- individually check each grammar
            fields = cpg[1](data)
            if fields then
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
        real_inject_message(msg)
    end
end


local mod_ref = "([^#]+)#(.+)"
local function get_module_ref(s)
    local mname, ref = string.match(s, mod_ref)
    local mr
    if mname then
        mr = require(mname)[ref]
    else
        local m = require(s)
        mr = m.grammar or m.syslog_grammar
    end
    return mr
end


local function get_decode_function(module_name)
    local decode = require(module_name).decode
    if type(decode) ~= "function"  then
        error(string.format("no decode function defined: %s", module_name))
    end
    return decode
end


local function load_transformations(t)
    for k,v in pairs(t) do
        local fn
        local mname, fname = string.match(v, mod_ref)
        if mname then fn = require(mname)[fname] end
        if type(fn) ~= "function" then
            error(string.format("invalid transformation function %s=%s", k, v))
        end
        t[k] = fn
    end
end


local function get_transform_decode_function(module_name, transformations)
    load_transformations(transformations)
    local im = function(msg, cp)
        if type(msg) ~= "table" then error("transformations expect msg to be a table") end
        for k,f in pairs(transformations) do
            f(msg, k)
        end
        real_inject_message(msg, cp)
    end
    interpose_inject_message(im)
    local decode = require(module_name).decode
    interpose_inject_message(real_inject_message)
    if type(decode) ~= "function"  then
        error(string.format("no decode function defined: %s", module_name))
    end
    return decode
end


local function load_decoder_impl(dcfg, grammars, sdk)
    local sdt = type(dcfg)
    if sdt == "string" then
        if dcfg:match("^decoders%.") then
            return get_decode_function(dcfg)
        else
            local g = get_module_ref(dcfg)
            if type(g) ~= "userdata" then
                error(string.format("sub_decoder, no grammar defined: %s", sdk))
            end
            return grammar_decode_fn(g)
        end
    elseif sdt == "table" then
        local nomatch_action
        for i,cpg in ipairs(dcfg) do
            if type(cpg) ~= "table" then
                cpg = {cpg}
                dcfg[i] = cpg
            end

            local fn
            local typ = type(cpg[1])
            if typ == "string" then
                if string.match(cpg[1], "^decoders%.") and #dcfg == 1 and not next(grammars) then
                    if not cpg[2] then
                        return get_decode_function(cpg[1])
                    else
                        return get_transform_decode_function(cpg[1], cpg[2])
                    end
                elseif (cpg[1] == DROP_TOKEN or cpg[1] == FAIL_TOKEN) and dcfg[i + 1] == nil then
                    nomatch_action = cpg[1]
                    dcfg[i] = nil
                    break
                end
                local g = printf.match_sample(grammars, cpg[1])
                if not g then
                    error(string.format("no grammar found for: %s", cpg[1]))
                end
                fn = grammar_fn(g)
            elseif typ == "table" then
                if string.match(cpg[1][1], "%%")  then -- printf specification
                    fn = grammar_fn(printf.build_grammar(cpg[1]))
                else
                    local g = get_module_ref(cpg[1][1])
                    local t = type(g)
                    if t == "function" then
                        fn = grammar_fn(g(unpack(cpg[1], 2)))
                    elseif t == "userdata" then
                        local len = #cpg[1]
                        if len > 1 then
                            fn = grammar_fn_args(g, cpg[1])
                        else
                            fn = grammar_fn(g)
                        end
                    else
                        error(string.format("invalid module reference %s", cpg[1][1]))
                    end
                end
            else
                error(string.format("sub_decoder: %s invalid entry: %d", sdk, i))
            end
            cpg[1] = fn
            if cpg[2] then load_transformations(cpg[2]) end
        end
        return grammar_pick_fn(dcfg, nomatch_action)
    else
        error(string.format("sub_decoder: %s invalid type: %s", sdk, sdt))
    end
end


function load_decoder(dcfg, pfm)
    local grammars = printf.load_messages(pfm or {})
    return load_decoder_impl(dcfg, grammars, "")
end
load_sub_decoder = load_decoder


function load_sub_decoders(sds, pfm)
    local sub_decoders  = {}
    local grammars = printf.load_messages(pfm or {})

    for sdk,dcfg in pairs(sds or {}) do
        if sdk == "*" then
            local fn = load_decoder_impl(dcfg, grammars, sdk)
            local mt = {__index = function(t, k) return fn end }
            setmetatable(sub_decoders, mt);
        else
            sub_decoders[sdk] = load_decoder_impl(dcfg, grammars, sdk)
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

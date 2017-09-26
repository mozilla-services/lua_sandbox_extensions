-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Logfmt Message Decoder Module

## Decoder Configuration Table for input cfg file
decoder_module = "decoders.logfmt"

-- Allows you to remap parsed logfmt tags into another field
logfmt_conf = {
    -- override root fields using Fields fields
    remap_hash_root = {
        time   = "Timestamp",
        host   = "Hostname",
        pid    = "Pid",
    },
    -- rename Fields fields
    remap_hash_fields = {
        app        = "Program",
        lvl        = "Severity",
        level      = "Severity",
        env        = "Environment",
        msg        = "Message",
        err        = "Error",
        from       = "From",
    },
    -- key -- cast function to apply on root fields after remaps
    cast_hash_root = {
        Pid         = "tonumber",
    },
    -- key -- cast function to apply on Fields fields after remaps
    cast_hash_fields = {
        ok         = "tonumber",
        ko         = "tonumber",
        queued     = "tonumber",
        discarded  = "tonumber",
        alert      = "tonumber",
        len        = "tonumber"
    }
}

## Functions

### decode

Decode and inject the resulting message

*Arguments*
- data (string) - logfmt message 

*Return*
- nil - throws an error on an invalid data type inject_message failure etc.

--]]

-- Read configuration
local cfg = read_config("logfmt_conf") or {}
cfg.remap_hash_root = cfg.remap_hash_root or {}
cfg.remap_hash_fields = cfg.remap_hash_fields or {}
cfg.cast_hash_root = cfg.cast_hash_root or {}
cfg.cast_hash_fields = cfg.cast_hash_fields or {}

-- Import
local inject_message = inject_message
local pairs          = pairs
local tostring       = tostring
local tonumber       = tonumber
local logfmt         = require 'lpeg.logfmt'
local print          = print
local tonumber       = tonumber
local tostring       = tostring

-- Will be used later for applying functions to fields
local cast_functions = {
    tonumber = tonumber,
    tostring = tostring
}

local M = {}

setfenv(1, M) -- Remove external access to contain everything in the module

if cfg.remap_hash then
    print("decoders.logfmt: remap hash found")
    for tag, target in pairs(cfg.remap_hash) do print("decoders.logfmt: ", tag," => ", target) end
end

function decode(data)
    local msg = { }
    local mapped = false
    local fields = logfmt:match(data)
    if not fields then return "parse failed" end

    msg.Type = "logfmt"
    msg.Payload = data

    msg.EnvVersion = "1.0"
    msg.Fields = {}

    for k,v in pairs(fields) do
        mapped = false
        -- rename fields at Root level
        if cfg.remap_hash_root[k] then
            msg[cfg.remap_hash_root[k]] = v
            mapped = true
        end
        -- rename fields at Fields level
        if cfg.remap_hash_fields[k] then
            msg.Fields[cfg.remap_hash_fields[k]] = v
            mapped = true
        end

        if not mapped then msg.Fields[k] = v end
    end

    -- process cast for root fields
    for tag, f in pairs(cfg.cast_hash_root) do
	if msg.Fields[tag] then
            msg.Fields[tag] = cast_functions[f](msg.Fields[tag])
        end
    end

    -- process cast for Fields fields
    for tag, f in pairs(cfg.cast_hash_fields) do
	if msg.Fields[tag] then
            msg.Fields[tag] = cast_functions[f](msg.Fields[tag])
        end
    end

    inject_message(msg)
end

return M

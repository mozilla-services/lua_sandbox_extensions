-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Sandbox Utility Module

## Functions

### table_to_fields

Flattens a Lua table so it can be encoded as a protobuf fields object.

*Arguments*
- hash (table) - table to flatten (not modified)
- fields (table) - table to receive the flattened output
- parent (string) - key prefix
- separator (string) - key separator (default = ".") i.e. 'foo.bar'
- max_depth (number) - maximum nesting before converting the remainder of the
  structure to a JSON string

*Return*
- none - in-place modification of `fields`

### table_to_message

Converts an arbitrary table into a heka message.

*Arguments*
* t (table) - input table
* tmap (table, nil) - transformation table
* msg (table, nil) - output table
* parent (string, nil) - key used if processing nested fields
```lua
tmap = {
    time = {header = "Timestamp"},
    size = {field  = "size", type = "string|bytes|int|double|boolean", representation = "MiB"}
}


*Return*
* msg - table in the Heka message schema format
--]]

-- Imports
local pairs     = pairs
local type      = type
local tostring  = tostring
local tonumber  = tonumber

local string = require "string"
local cjson = require "cjson"

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local function transform_to_field(t, k, v, vtype, vrep)
    if not t.Fields then t.Fields = {} end

    local typ = type(v)
    if vtype then
        if vtype == "string" or vtype == "bytes" then
            if typ == "table" then
                v = cjson.encode(v)
            elseif typ == "userdata" then
                -- no op, allow the object to handle the conversion on inject_message
            else
                v = tostring(v)
            end
        elseif vtype == "int" or vtype == "double" then
            if typ == "number" then
                -- no-op
            elseif typ == "boolean" then
                if v then
                   v = 1
                else
                   v = 0
                end
            elseif typ == "string" then
                v = tonumber(v)
            else
                return -- skip
            end
        elseif vtype == "boolean" then
            if typ == "boolean" then
                -- no-op
            elseif typ == "number" then
                v = (v ~= 0)
            elseif typ == "string" then
                if v == "true" or v == "TRUE" then
                    v = 1
                else
                    v = 0
                end
            else
                return -- skip
            end
        end

        if vtype == "bytes" then
            vtype = 1
        elseif vtype == "int" then
            vtype = 2
        else
            vtype = nil
        end
    else
        if typ == "table" then v = cjson.encode(v) end
    end

    if vtype or vrep then
        t.Fields[k] = {value = v, value_type = vtype, representation = vrep}
    else
        t.Fields[k] = v
    end
end


local function transform_to_header(t, k, v)
    if k == "Uuid" or k == "Logger" or k == "Hostname" or k == "Type"
    or k == "Payload" or k == "EnvVersion" or k == "Timestamp" or k == "Pid"
    or k == "Severity" then
        t[k] = v
    else
        transform_to_field(t, k, v)
    end
end


function table_to_fields(t, fields, parent, char, max_depth)
    if type(char) ~= "string" then
        char = "."
    end

    for k,v in pairs(t) do
        if parent then
            full_key = string.format("%s%s%s", parent, char, k)
        else
            full_key = k
        end

        if type(v) == "table" then
            local _, sep_count = string.gsub(full_key, "%" .. char, "")
            local depth = sep_count + 1

            if type(max_depth) == "number" and depth >= max_depth then
                fields[full_key] = cjson.encode(v)
            else
                table_to_fields(v, fields, full_key, char, max_depth)
            end
        else
            if type(v) ~= "userdata" then
                fields[full_key] = v
            end
        end
    end
end


function table_to_message(t, tmap, msg, parent)
    if type(t) ~= "table" then
        return
    end
    if type(tmap) ~= "table" then tmap = {} end
    if not msg then msg = {} end

    for k,v in pairs(t) do
        local m = tmap[k]
        if not m then
            if not parent or parent == "" then
                transform_to_header(msg, k, v)
            else
                transform_to_field(msg, string.format("%s.%s", parent, k), v)
            end
        elseif m.header then
            msg[m.header] = v
        elseif m.field and type(m.field) == "string" then
            transform_to_field(msg, m.field, v, m.type, m.representation)
        else
            if parent then
                p = string.format("%s.%s", parent, k)
            else
                p = k
            end
            table_to_message(v, m, msg, p)
        end
    end
    return msg
end

return M

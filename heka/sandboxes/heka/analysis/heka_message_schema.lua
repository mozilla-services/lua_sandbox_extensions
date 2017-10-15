-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Message Schema Display

Generates documentation for each unique message in a data stream.  The output is
a hierarchy of Logger, Type, EnvVersion, and a list of associated message field
attributes including their counts (number in the brackets). This plugin is meant
for data discovery/exploration and should not be left running on a production
system.

## Sample Configuration

```lua
filename = "heka_message_schema.lua"
ticker_interval = 60
preserve_data = false
message_matcher = "TRUE"
```

## Sample Output
```
Logger -> Type -> EnvVersion -> Field Attributes.
The number in brackets is the number of occurrences of each logger/type/attribute.

fx [14482]
    executive_summary [14482]
         -no version- [14482]
            other (integer - optional [14407])
            app (string)
            vendor (string)
```
--]]

local schema  = {}

local function get_type(t)
    if t == -1 then
        return "mismatch"
    elseif t == 1 then
        return "binary"
    elseif t == 2 then
        return "integer"
    elseif t == 3 then
        return "double"
    elseif t == 4 then
       return "bool"
    end
    return "string" -- default
end

local function get_parquet_type(t)
    if t == -1 then
        return "mismatch"
    elseif t == 1 then
        return "binary"
    elseif t == 2 then
        return "int64"
    elseif t == 3 then
        return "double"
    elseif t == 4 then
       return "boolean"
    end
    return "binary" -- default
end

local function get_entry_table(t, key)
    local v = t[key]
    if not v then
        v = {}
        v.cnt = 0
        v.headers = {
            Uuid        = {cnt = 0, type = "fixed_len_byte_array(16)"},
            Timestamp   = {cnt = 0, type = "int64"},
            Logger      = {cnt = 0, type = "binary"},
            Hostname    = {cnt = 0, type = "binary"},
            Type        = {cnt = 0, type = "binary"},
            Payload     = {cnt = 0, type = "binary"},
            EnvVersion  = {cnt = 0, type = "binary"},
            Pid         = {cnt = 0, type = "int32"},
            Severity    = {cnt = 0, type = "int32"},
        }
        v.fields = {}
        t[key] = v
    end
    v.cnt = v.cnt + 1

    return v
end

local function get_table(t, key)
    local v = t[key]
    if not v then
        v = {}
        v.cnt = 0
        t[key] = v
    end
    v.cnt = v.cnt + 1
    return v
end

local function output_headers(t, cnt)
    for k, v in pairs(t) do
        add_to_payload("            ", k)
        if cnt ~= v.cnt then
            add_to_payload(" - optional [", v.cnt, "]")
        end
        add_to_payload("\n")
    end
end

local function output_parquet_headers(t, cnt)
    for k, v in pairs(t) do
        add_to_payload("                ")
        if cnt ~= v.cnt then
            add_to_payload("optional ")
        else
            add_to_payload("required ")
        end
        add_to_payload(v.type, " ", k, ";\n")
    end
end

local function output_fields(t, cnt)
    add_to_payload("            -Fields-\n")
    for k, v in pairs(t) do
        add_to_payload("                ", k, " (", get_type(v.type))
        if v.repetition then
            add_to_payload("[]")
        end
        if v.representation then
            add_to_payload(" (", v.representation, ")")
        end
        if cnt ~= v.cnt then
            add_to_payload(" - optional [", v.cnt, "]")
        end
        add_to_payload(")\n")
    end
end


local function output_parquet_fields(t, cnt)
    add_to_payload("                required group Fields {\n")
    for k, v in pairs(t) do
        add_to_payload("                    ")
        if v.repetition then
            add_to_payload("repeated ")
        elseif cnt ~= v.cnt then
            add_to_payload("optional ")
        else
            add_to_payload("required ")
        end
        add_to_payload(get_parquet_type(v.type), " ", k, ";\n")
    end
    add_to_payload("                }\n")
end


local function output_versions(t, parquet)
    for k, v in pairs(t) do
        if type(v) == "table" then
            local cnt = v.cnt
            if k == "" then
                k = "-no version-"
            end
            add_to_payload("        ", k, " [", cnt, "]\n")
            if parquet then
                add_to_payload("            message schema {\n")
                output_parquet_headers(v.headers, cnt)
                output_parquet_fields(v.fields, cnt)
                add_to_payload("            }\n")
            else
                output_headers(v.headers, cnt, parquet)
                output_fields(v.fields, cnt, parquet)
            end
        end
    end
end

local function output_types(t, parquet)
    for k, v in pairs(t) do
        if type(v) == "table" then
            if k == "" then
                k = "-no type-"
            end
            add_to_payload("    ", k, " [", v.cnt, "]\n")
            output_versions(v, parquet)
        end
    end
end

local function output_loggers(schema, parquet)
    for k, v in pairs(schema) do
        if type(v) == "table" then
            if k == "" then
                k = "-no logger-"
            end
            add_to_payload(k, " [", v.cnt, "]\n")
            output_types(v, parquet)
        end
    end
end

function process_message()
    local msg = decode_message(read_message("raw"))
    local l = get_table(schema, msg.Logger or "")
    local t = get_table(l, msg.Type or "")
    local v = get_entry_table(t, msg.EnvVersion or "")

    for m,n in pairs(v.headers) do
        if msg[m] then
            n.cnt = n.cnt + 1
        end
    end

    if not msg.Fields then return 0 end

    for i, f in ipairs(msg.Fields) do
        local entry = v.fields[f.name]
        if entry then
            entry.cnt = entry.cnt + 1
            if f.value_type ~= entry.type then
                entry.type = -1 -- mis-matched types
            end
        else
            v.fields[f.name] = {cnt = 1, type = f.value_type, representation = f.representation, repetition = #f.value > 1}
        end
    end
    return 0
end

function timer_event(ns, shutdown)
    add_to_payload("Logger -> Type -> EnvVersion -> Field Attributes.\n",
           "The number in brackets is the number of occurrences of each logger/type/attribute.\n\n")
    output_loggers(schema)
    inject_payload("txt", "Message Schema")

    output_loggers(schema, true)
    inject_payload("txt", "parquet")
end


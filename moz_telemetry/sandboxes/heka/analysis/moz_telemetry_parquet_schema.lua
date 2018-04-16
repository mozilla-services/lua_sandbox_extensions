-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry Parquet Schema Documentation

Generates parquet schema documentation for each docType in the data stream.

## Sample Configuration

```lua
filename = "moz_telemetry_parquet_schema.lua"
message_matcher = "Uuid < '\003' && Fields[docType] != NIL" -- slightly greater than a 1% sample
ticker_interval = 60
preserve_data = false
```

## Sample Output

Hierarchy:
1. msg.Type
    1. msg.Fields[docType]
        1. msg.Fields[sourceVersion]

The number in brackets is the number of occurrences of each dimension in the sample.
```
telemetry.duplicate [1415]
    first-shutdown [12]
        -no version- [12]
            message schema {
                required binary Logger (UTF8);
                required fixed_len_byte_array(16) Uuid;
                optional int32 Pid;
                optional int32 Severity;
                optional binary EnvVersion (UTF8);
                required binary Hostname (UTF8);
                required int64 Timestamp;
                optional binary Payload (UTF8);
                required binary Type (UTF8);
                required group Fields {
                    optional binary geoSubdivision1 (UTF8);
                    required binary appUpdateChannel (UTF8);
                    required binary documentId (UTF8);
                    required binary docType (UTF8);
                    required int64 duplicateDelta;
                    required binary geoCountry (UTF8);
                    required binary geoCity (UTF8);
                    required binary appVersion (UTF8);
                    required binary appBuildId (UTF8);
                    required binary appName (UTF8);
                }
            }
```
--]]

local schema  = {}

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


local function output_parquet_headers(t, cnt)
    for k, v in pairs(t) do
        add_to_payload("                ")
        if cnt ~= v.cnt then
            add_to_payload("optional ")
        else
            add_to_payload("required ")
        end
        local meta = ""
        if v.type == "binary" then meta = " (UTF8)" end
        add_to_payload(v.type, " ", k, meta, ";\n")
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
        local meta = ""
        local t = get_parquet_type(v.type)
        if t == "binary" then meta = " (UTF8)" end
        add_to_payload(t, " ", k, meta, ";\n")
    end
    add_to_payload("                }\n")
end


local function output_versions(t)
    for k, v in pairs(t) do
        if type(v) == "table" then
            local cnt = v.cnt
            if k == "" then k = "-no version-" end
            add_to_payload("        ", k, " [", cnt, "]\n")
            add_to_payload("            message schema {\n")
            output_parquet_headers(v.headers, cnt)
            output_parquet_fields(v.fields, cnt)
            add_to_payload("            }\n")
        end
    end
end


local function output_types(t)
    for k, v in pairs(t) do
        if type(v) == "table" then
            add_to_payload("    ", k, " [", v.cnt, "]\n")
            output_versions(v)
        end
    end
end


local function output_loggers(schema)
    for k, v in pairs(schema) do
        if type(v) == "table" then
            if k == "" then
                k = "-no Type-"
            end
            add_to_payload(k, " [", v.cnt, "]\n")
            output_types(v)
        end
    end
end


function process_message()
    local msg = decode_message(read_message("raw"))
    local l = get_table(schema, msg.Type or "")
    local t = get_table(l, read_message("Fields[docType]"))
    local v = get_entry_table(t, read_message("Fields[sourceVersion]") or "")

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
    output_loggers(schema)
    inject_payload("txt", "parquet")
end

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

local cnt_key = "_cnt_"

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

local function get_table(t, key)
    local v = t[key]
    if not v then
        v = {}
        v[cnt_key] = 0
        t[key] = v
    end
    v[cnt_key] = v[cnt_key] + 1

    return v
end

local function output_fields(t, cnt)
    for k, v in pairs(t) do
        if k ~= cnt_key then
            add_to_payload("            ", k, " (", get_type(v.type))
            if v.representation then
                add_to_payload(" (", representation, ")")
            end
            if cnt ~= v[cnt_key] then
                add_to_payload(" - optional [", v[cnt_key], "]")
            end
            add_to_payload(")\n")
        end
    end
end

local function output_versions(t)
    for k, v in pairs(t) do
        if type(v) == "table" then
            local cnt = v[cnt_key]
            if k == "" then
                k = "-no version-"
            end
            add_to_payload("         ", k, " [", cnt, "]\n")
            output_fields(v, cnt)
        end
    end
end

local function output_types(t)
    for k, v in pairs(t) do
        if type(v) == "table" then
            if k == "" then
                k = "-no type-"
            end
            add_to_payload("    ", k, " [", v[cnt_key], "]\n")
            output_versions(v)
        end
    end
end

local function output_loggers(schema)
    for k, v in pairs(schema) do
        if type(v) == "table" then
            if k == "" then
                k = "-no logger-"
            end
            add_to_payload(k, " [", v[cnt_key], "]\n")
            output_types(v)
        end
    end
end

function process_message()
    local msg = decode_message(read_message("raw"))
    local l = get_table(schema, msg.Logger or "")
    local t = get_table(l, msg.Type or "")
    local v = get_table(t, msg.EnvVersion or "")

    if not msg.Fields then return 0 end

    for i, f in ipairs(msg.Fields) do
        local entry = v[f.name]
        if entry then
            entry[cnt_key] = entry[cnt_key] + 1
            if f.value_type ~= entry.type then
                entry.type = -1 -- mis-matched types
            end
        else
            v[f.name] = {[cnt_key] = 1, type = f.value_type, representation = f.representation}
        end
    end
    return 0
end

function timer_event(ns, shutdown)
    add_to_payload("Logger -> Type -> EnvVersion -> Field Attributes.\n",
           "The number in brackets is the number of occurrences of each logger/type/attribute.\n\n")
    output_loggers(schema)
    inject_payload("txt", "Message Schema")
end


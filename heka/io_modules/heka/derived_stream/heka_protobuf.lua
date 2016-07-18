-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Protobuf Helper Functions

## Functions

### write_message

Apply the schema and write the formatted message to disk.

*Arguments*
- fh (userdata) - file handle
- msg (table) - heka message table
- schema (table) - schema table

*Return*
- *none*
--]]

local M = {}
local ipairs    = ipairs
local type      = type
local match     = require "string".match

local read_message      = read_message
local encode_message    = encode_message

setfenv(1, M) -- Remove external access to contain everything in the module

function write_message(fh, msg, schema)
    for i,v in ipairs(schema) do
        local value
        if type(v[5]) == "function" then
            value = v[5]()
        elseif type(v[5]) == "string" then
            value = read_message(v[5])
        end

        if value ~= nil then
            if v[1] == "Uuid" then
                msg.Uuid = value
            elseif v[1] == "Timestamp" then
                msg.Timestamp = value
            elseif v[1] == "Type" then
                msg.Type = value
            elseif v[1] == "Logger" then
                msg.Logger = value
            elseif v[1] == "Severity" then
                msg.Severity = value
            elseif v[1] == "EnvVersion" then
                msg.EnvVersion = value
            elseif v[1] == "Pid" then
                msg.Pid = value
            elseif v[1] == "Hostname" then
                msg.Hostname = value
            else
                if type(value) == "number" and match(v[2], "INT") then
                    msg.Fields[v[1]] = {value = value, value_type = 2}
                else
                    msg.Fields[v[1]] = value
                end
            end
        end
    end
    fh:write(encode_message(msg, true))
end

return M

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Telemetry S3 Path Dimension Specification Parser/Zalidator

## Functions

### validate_dimensions

Loads and validates the dimension specification from disk.

*Arguments*
* filename (string) - name of the file containing the JSON dimension specification

*Return*
* table - contains the parsed/validated dimensions array with the following modifications
  * `header_name` is re-mapped to `field_name` and and field_name values are expanded to 'Fields[`name`]'
  * `matcher_type` string is added (wildcard|string|list|minmax)
  * `matcher` function is added (returns true if a value matches the specification)

### sanitize_dimension

Returns a string suitable for use as an S3 path component.

*Arguments*
* value (string, number, bool) - converted to a string, sanitized and returned

*Return*
* string - nil if the value was not convertible to a string


## Dimension Specification

### Sample Dimension Specification
```json
  {
    "version": 1,
    "dimensions": [
      {"header_name": "Type", "allowed_values": "telemetry"},

      {"field_name": "submissionDate", "allowed_values": {"min": "20140120", "max": "20140125"}},
      {"field_name": "sourceName", "allowed_values": "*"},
      {"field_name": "sourceVersion", "allowed_values": "*"},
      {"field_name": "reason", "allowed_values": ["idle-daily", "saved-session"]},
      {"field_name": "appName", "allowed_values": ["Firefox", "Fennec"]},
      {"field_name": "appUpdateChannel", "allowed_values": ["nightly", "beta", "release"]},
      {"field_name": "appVersion", "allowed_values": "*"}
    ]
  }
```
Note: This specification does not include:
* field/array index support
* pattern matches
--]]

-- Imports
local assert    = assert
local error     = error
local ipairs    = ipairs
local tostring  = tostring
local type      = type

local cjson     = require "cjson"
local io        = require "io"
local string    = require "string"

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module


local function is_in_list(v, av)
    for i, j in ipairs(av) do
        if v == j then return true end
    end
    return false
end


local function is_in_range(v, min, max)
    if min and v < min then return false end
    if max and v > max then return false end
    return true
end


function validate_dimensions(fn)
    local fh = assert(io.open(fn))
    local json = fh:read("*a")
    fh:close()

    local df = cjson.decode(json)
    for i,d in ipairs(df.dimensions) do
        local name
        if d.header_name then
            name = d.header_name
            if name ~= "Uuid" and name ~= "Timestamp" and name ~= "Type"
            and name ~= "Logger" and name ~= "Severity" and name ~= "Payload"
            and name ~= "EnvVersion" and name ~= "Pid" and name ~= "Hostname" then
                error("invalid header name " .. name)
            end
            d.header_name = nil
        else
            name = string.format("Fields[%s]", d.field_name)
        end
        d.field_name = name
        local av = d.allowed_values
        if type(av) == "string" then
            if av == "*" then
                d.matcher = function (v) return true end
                d.matcher_type = "wildcard"
            else
                av = sanitize_dimension(av)
                d.matcher = function (v) return v == av end
                d.matcher_type = "string"
            end
        elseif type(av) == "table" then
            if av[1] ~= nil then
                for m,n in ipairs(av) do
                    if type(n) ~= "string" then
                        error(string.format("field '$s' allowed_values array must contain only strings", name))
                    end
                    av[m] = sanitize_dimension(n)
                end
                d.matcher = function (v) return is_in_list(v, av) end
                d.matcher_type = "list"
            else
                if not av.min and not av.max then
                    error(string.format("field '%s' allowed_values range must have a 'min' or 'max'", name))
                end
                if av.min and type(av.min) ~= "string"
                or av.max and type(av.max) ~= "string" then
                    error(string.format("field '%s' allowed_values range min/max must be a string", name))
                end
                d.matcher = function (v) return is_in_range(v, av.min, av.max) end
                d.matcher_type = "minmax"
            end
        else
            error(string.format("field '%s' allowed_values invalid type: %s", type(av)))
        end
    end
    return df.dimensions
end


function sanitize_dimension(d)
    if d ~= nil then
        return string.gsub(tostring(d), "[^a-zA-Z0-9_.]", "_")
    end
end

return M

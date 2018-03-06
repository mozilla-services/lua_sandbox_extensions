-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Message Extensions with GeoIP2 Information

This module is intended to be used with another IO module such as a decoder to
extend the message with GeoIP2 information prior to injection.

## Functions

### add_geoip

Given a Heka message add the geoip entries based on the specified field name.
The requested geoip entries are specified in the `databases` configuration
table. The table is &lt;db_filename&gt; = &lt;lookup table&gt;. The lookup table
is &lt;suffix&gt; = &lt;path array&gt; (an empty suffix will overwrite the
original value). The path specification is specific to the database being
queried.

*Arguments*
- msg (table) - original message
- field_name (string) - field name in the message to lookup

*Return*
- none - the message is modified in place or an error is thrown

## Configuration examples
```lua
maxminddb_heka = {
    databases = {
        ["GeoIP2-City-Test.mmdb"] = {
            _city = {"city", "names", "en"},
            _country = {"country", "iso_code"}
        },
        ["GeoIP2-ISP-Test.mmdb"] = {
            _isp = {"isp"}
        },
    },
    remove_original_field = false, -- remove the original field after a successful lookup
}
```
--]]
local module_name = ...
local module_cfg  = require "string".gsub(module_name, "%.", "_")
local cfg         = read_config(module_cfg) or error(module_name .. " configuration not found")
assert(type(cfg.databases) == "table", "databases configuration must be a table")

local mm        = require "maxminddb"
local databases = {}
for k,v in pairs(cfg.databases) do
    if type(v) ~= "table" then
        error(string.format("invalid database entry: %s", k))
    end
    local ok, db = pcall(mm.open, k)
    if not ok then error("error opening: " .. k) end
    databases[k] = {lookups = v, db = db}
end
assert(next(databases) ~= nil, "databases must contain at least one entry")

local smatch    = string.match
local assert    = assert
local ipairs    = ipairs
local pairs     = pairs
local pcall     = pcall
local type      = type
local unpack    = unpack

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module.

local function validate_ip(ip)
    local sl = #ip
    return not (sl < 7 or sl > 15 or not smatch(ip, "^%d+%.%d+%.%d+%.%d+$"))
end


local function add_array(msg, field_name, values)
    local update = false
    for _, t in pairs(databases) do
        local found = false
        local ips = {}
        local cnt = 0
        for i,j in ipairs(values) do
            if validate_ip(j) then
                local ok, ret = pcall(t.db.lookup, t.db, j)
                if ok then
                    ips[i] = ret
                else
                    ips[i] = nil
                end
            end
            cnt = i
        end

        for suffix, path in pairs(t.lookups) do
            local fname = field_name .. suffix
            local items = {}
            for i=1, cnt do
                local geo
                local ip = ips[i]
                if ip then
                    local ok, value = pcall(ip.get, ip, unpack(path))
                    if ok then
                        geo = value
                        found = true
                    end
                end
                items[i] = geo or ""
            end
            if found then
                updated = true
                msg.Fields[fname] = items
            end
        end
    end

    if updated and cfg.remove_original_field then
        msg.Fields[field_name] = nil
    end
end


function add_geoip(msg, field_name)
    if not msg.Fields then return end
    local value = msg.Fields[field_name]
    local vt = type(value)
    if vt == "table" then
        if value.value then  -- Heka schema
            value = value.value
        end
        vt = type(value)
        if vt == "table" then -- array of values
            add_array(msg, field_name, value)
            return
        end
    end
    if vt ~= "string" or not validate_ip(value) then return end

    local found = false
    for _, t in pairs(databases) do
        local ok, ret = pcall(t.db.lookup, t.db, value)
        if ok then
            for suffix, path in pairs(t.lookups) do
                local ok, value = pcall(ret.get, ret, unpack(path))
                if ok then
                    found = true
                    msg.Fields[field_name .. suffix] = value
                end
            end
        end
    end

    if found and cfg.remove_original_field then
        msg.Fields[field_name] = nil
    end
end

return M

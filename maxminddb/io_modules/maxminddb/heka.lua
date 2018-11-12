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

### add_geoip_xff

Given a Heka message add the geoip entries based on the specified field name
containing an `x_forwarded_for` string. Use the `xff` configuration option to
control the address selection.

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
    -- xff = "last|first|all", -- default last

}
```
--]]
local module_name = ...
local module_cfg  = require "string".gsub(module_name, "%.", "_")
local cfg         = read_config(module_cfg) or error(module_name .. " configuration not found")
assert(type(cfg.databases) == "table", "databases configuration must be a table")
if cfg.xff then
    assert(cfg.xff == "last" or cfg.xff == "first" or cfg.xff == "all", "invalid xff cfg value")
else
    cfg.xff = "last"
end

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

local string    = require "string"
local assert    = assert
local ipairs    = ipairs
local pairs     = pairs
local pcall     = pcall
local type      = type
local unpack    = unpack

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module.

local ip_pattern  = "%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?"
local ip_anchored = "^" .. ip_pattern .. "$"


local function add_array(msg, field_name, values)
    local update = false
    for _, t in pairs(databases) do
        local found = false
        local ips = {}
        local cnt = 0
        for i,j in ipairs(values) do
            if j:match(ip_anchored) then
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


local function lookup(msg, field_name, ip)
    local found = false
    for _, t in pairs(databases) do
        local ok, ret = pcall(t.db.lookup, t.db, ip)
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
    if vt ~= "string" or not value:match(ip_anchored) then return end
    lookup(msg, field_name, value)
end


function add_geoip_xff(msg, field_name)
    if not msg.Fields then return end
    local value = msg.Fields[field_name]
    if type(value) ~= "string" then return end

    local ips = {}
    for ip in value:gmatch(ip_pattern) do
        ips[#ips + 1] = ip
    end
    local cnt = #ips
    if cnt == 0 then return end

    if cfg.xff == "last" then
        lookup(msg, field_name, ips[cnt])
    elseif cfg.xff == "first" then
        lookup(msg, field_name, ips[1])
    else
        add_array(msg, field_name, ips)
    end
end

return M

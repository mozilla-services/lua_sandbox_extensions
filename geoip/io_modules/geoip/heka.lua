-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Message Extensions with GeoIP information

This module is intended to be used with another IO module such as a decoder to
extend the message with GeoIP information prior to injection.

## Functions

### add_geoip

Given a Heka message add the geoip entries based on the specified field name.
The requested geoip entries are specified in the `lookup` configuration table.
The table consists of the entry name and the suffix to add to the field name,
an empty suffix will overwrite the original value. See: the `opts` variable in
https://github.com/agladysh/lua-geoip/blob/master/src/city.c for the available
options, common values include "city" and "country_code".

For example, if "remote_addr" is present in msg.Fields with a cfg of `lookup =
{ city = "_city" }` on a successful lookup a new field will be added to the
message named "remote_addr_city" with the resulting city value.

*Arguments*
- msg (table) - original message
- field_name (string) - field name in the message to lookup

*Return*
- none - the message is modified in place or an error is thrown

## Configuration examples
```lua
geoip_heka = {
    city_db_file = "/path/to/geo/dat", -- path to GeoIP data
    lookup = { city = "_city", country_code = "_country" }, -- entries to lookup and their field suffix

    test = false, -- true if being used in tests without GeoIP database
}
```
--]]
local module_name = ...
local module_cfg  = require "string".gsub(module_name, "%.", "_")
local cfg         = read_config(module_cfg) or error(module_name .. " configuration not found")
assert(type(cfg.lookup) == "table" and next(cfg.lookup) ~= nil, "lookup configuration must be a table")

local geoip     = require "geoip.city"
local ostime    = require "os".time
local smatch    = string.match
local assert    = assert
local pairs     = pairs
local type      = type

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module.

local gtest = {}

-- In test mode, returns Mountain View, US for 192.168.1.2 otherwise nil, only
-- supports country_code and city lookup values
local test_return = {country_code = "US", city = "Mountain View"}
function gtest:query_by_addr(v, lookup)
    if v == "192.168.1.2" then
        return test_return[lookup]
    end
end

local ptime = 0
local geodb = nil
local function refresh_db()
    local ctime = ostime()
    if ptime + 3600 < ctime then
        if geodb then geodb:close() end
        geodb = assert(geoip.open(cfg.city_db_file))
        ptime = ctime
    end
end


local function validate_ip(ip)
    local sl = #ip
    return not (sl < 7 or sl > 15 or not smatch(ip, "^%d+%.%d+%.%d+%.%d+$"))
end


if cfg.test then
    geodb = gtest
    refresh_db = function () return end
else
    refresh_db()
end

function add_geoip(msg, field_name)
    if not msg.Fields then return end
    local value = msg.Fields[field_name]
    if type(value) ~= "string" or not validate_ip(value) then return end

    refresh_db()

    for k,v in pairs(cfg.lookup) do
        local ret = geodb:query_by_addr(value, k)
        if ret then
            msg.Fields[field_name .. v] = ret
            if cfg.remove_original_field then
                msg.Fields[field_name] = nil
            end
        end
    end
end


return M

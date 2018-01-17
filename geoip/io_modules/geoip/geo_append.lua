-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Message Extensions with GeoIP information

This module is intended to be used with another IO module such as a decoder to extend
the message with GeoIP information prior to injection.

## Functions

### geo_append

Given a message, attempt to geolocate any fields (specified by the fields configuration
option). The lookup configuration option specifies the types of location that will occur.

Valid key values for the lookup configuration option include options that would be passed as
a lookup type to the geoip query_by_addr function. The current list of valid options can be
seen at https://github.com/agladysh/lua-geoip/blob/master/src/city.c in the opts variable,
common values will include "city" and "country_code".

For example, if "remote_addr" is present in fields, and lookup is "{ city = "city" }", if
we can geolocate the address a new field will be added called remote_addr_city which contains
the results of the geolocation.

*Arguments*
- msg (table) - original message

*Return*
- msg (table) - message possibly modified with new fields

## Configuration examples
```lua
geo_append = {
    path = "/path/to/geo/dat", -- path to GeoIP data
    test = false, -- true if being used in tests without GeoIP database
    fields = { "remote_addr" }, -- Fields to attempt to geolocate
    lookup = { city = "city", country_code = "country" }, -- lookup types
}
```
--]]

local geoip     = require "geoip.city"
local ostime    = require "os".time
local floor     = require "math".floor
local sformat   = require "string".format
local slen      = string.len
local smatch    = string.match

local module_name = ...
local module_cfg = require "string".gsub(module_name, "%.", "_")
local config = read_config(module_cfg) or error("geo_append configuration not found")

local assert    = assert
local pairs     = pairs
local error     = error
local pcall     = pcall

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module.

local gtest = {}

-- In test mode, returns Mountain View, US for 192.168.1.2 otherwise nil, only
-- supports country_code and city lookup values
function gtest:query_by_addr(v, lookup)
    if v ~= "192.168.1.2" then
        return nil
    end
    if lookup == "country_code" then
        return "US"
    elseif lookup == "city" then
        return "Mountain View"
    end
    return nil
end

local function geo_query(f, p)
    return config.geoip:query_by_addr(f, p)
end

local function geo_config()
    if not config.test then
        config.geoip = assert(geoip.open(config.path))
    else
        config.geoip = gtest
    end
    if not config.lookup then
        error("geo_append configuration contains no lookup option")
    end
    if not config.fields then
        error("geo_append configuration contains no fields option")
    end
    local c = 0
    for k,v in pairs(config.fields) do
        c = c + 1
    end
    if c == 0 then
        error("geo_append configuration contains no fields")
    end
    config.hour = floor(ostime() / 3600)
    return config
end

local function geo_refresh()
    if config.test then
        return
    end
    local chour = floor(ostime() / 3600)
    if chour > config.hour then
        config.geoip:close()
        config.geoip = assert(geoip.open(config.path))
        config.hour = chour
    end
end

local function geo_validate(ip)
    local sl = slen(ip)
    if sl < 7 or sl > 15 or not smatch(ip, "^%d+%.%d+%.%d+%.%d+$") then
        return false
    end
    return true
end

geo_config()

function geo_append(msg)
    geo_refresh()

    if not msg.Fields then
        return msg
    end

    local omsg = msg
    for k,v in pairs(config.fields) do
        if omsg.Fields[v] then
            if geo_validate(omsg.Fields[v]) then
                for ik, iv in pairs(config.lookup) do
                    local ks = sformat("%s_%s", v, iv)
                    local s, ret = pcall(geo_query, omsg.Fields[v], ik)
                    if s and ret then
                        msg.Fields[ks] = ret
                    end
                end
            end
        end
    end

    return msg
end

return M

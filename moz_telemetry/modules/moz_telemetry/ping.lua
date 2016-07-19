-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry Data Normalization Module

## Functions

### build
Returns the environment.build JSON object as a Lua table.

### system
Returns the environment.system JSON object as a Lua table.

### addons
Returns the environment.addons JSON object as a Lua table.

### num_active_addons
Returns the number of active addons.

### flash_version
Returns the flash version or nil if not available.

### settings
Returns the environment.settings JSON object as a Lua table.

### is_default_browser
Returns true if Firefox is the default browser.

### profile_creation_timestamp
Returns the profile creation timestamp in nano seconds since Jan 1, 1970.

### khist
Returns the payload.keyedHistograms JSON object as a Lua table.

### khist_sum

*Arguments*
- section (string)
- key (string

*Return*
- sum (number) - returns the sum of the histogram values for the specified
  section/key

### info
Returns the payload.info JSON object as a Lua table.

### hours
Returns the subsession uptime in hours (e.g. 1.25).

### payload
Returns the message payload JSON object as a Lua table.

### get_timestamp

*Arguments*
- timestring (string) - rfc3339 or crash date format

*Return*
- timestamp (number) - timestamp in nano seconds since Jan 1, 1970

### get_date

*Arguments*
- timestring (string) - crash date format

*Return*
- date (string) - YY-MM-DD
--]]

local M = {}
local ipairs    = ipairs
local pairs     = pairs
local pcall     = pcall
local tonumber  = tonumber
local type      = type
local cjson     = require "cjson"
local dt        = require "lpeg.date_time"
local l         = require "lpeg"
l.locale(l)
local format    = require "string".format

local read_message = read_message

setfenv(1, M) -- Remove external access to contain everything in the module

local crash_date        = dt.build_strftime_grammar("%Y-%m-%d")
local integer           = l.digit^1/tonumber
local flash_ver_grammar = l.Ct(integer * "." * integer * "." * integer * "." * integer)
local cache             = {} -- cache to store the parsed json components while working with a message
local SEC_IN_HOUR       = 60 * 60
local SEC_IN_DAY        = SEC_IN_HOUR * 24


function clear_cache()
    cache = {}
end


function build()
    if not cache.build then
        local json = read_message("Fields[environment.build]")
        local ok
        ok, cache.build = pcall(cjson.decode, json)
        if not ok then cache.build = {} end
    end
    return cache.build
end


function system()
    if not cache.system then
        local json = read_message("Fields[environment.system]")
        local ok
        ok, cache.system = pcall(cjson.decode, json)
        if not ok then cache.system = {} end

        if type(cache.system.os) ~= "table" then
            cache.system.os = {}
        end
    end
    return cache.system
end


function addons()
    if not cache.addons then
        local json = read_message("Fields[environment.addons]")
        local ok
        ok, cache.addons = pcall(cjson.decode, json)
        if not ok then cache.addons = {} end

        if type(cache.addons.activeExperiment) ~= "table" then
            cache.addons.activeExperiment = {}
        end
    end
    return cache.addons
end


function num_active_addons()
    local addons = addons()
    local cnt = 0
    if type(addons.activeAddons) == "table" then
        for k,v in pairs(addons.activeAddons) do
            cnt = cnt + 1
        end
    end
    return cnt
end


function flash_version()
    local addons = addons()
    local version
    if type(addons.activePlugins) == "table" then
        for i,v in ipairs(addons.activePlugins) do
            if type(v) == "table" and v.name == "Shockwave Flash" then
                if type(v.version) ~= "string" then v.version = "" end
                local sv = flash_ver_grammar:match(v.version)
                if sv then
                    if not version
                    or sv[1] > version[1]
                    or sv[2] > version[2]
                    or sv[3] > version[3]
                    or sv[4] > version[4] then
                        sv[5] = v.version
                        version = sv
                    end
                end
            end
        end
        if version then version = version[5] end
    end
    return version
end


function settings()
    if not cache.settings then
        local json = read_message("Fields[environment.settings]")
        local ok
        ok, cache.settings = pcall(cjson.decode, json)
        if not ok then cache.settings = {} end
    end
    return cache.settings
end


function is_default_browser()
    local settings = settings()
    local b = settings.isDefaultBrowser
    if type(b) == "boolean" then
        return b
    end
    return false
end


function profile()
    if not cache.profile then
        local json = read_message("Fields[environment.profile]")
        local ok
        ok, cache.profile = pcall(cjson.decode, json)
        if not ok then cache.profile = {} end
    end
    return cache.profile
end


function profile_creation_timestamp()
    local profile = profile()
    local days = profile.creationDate
    if type(days) == "number" and days > 0 then
        return days * SEC_IN_DAY * 1e9
    end
    return 0
end


function khist()
    if not cache.khist then
        local json = read_message("Fields[payload.keyedHistograms]")
        local ok
        ok, cache.khist = pcall(cjson.decode, json)
        if not ok then cache.khist = {} end
    end
    return cache.khist
end


function khist_sum(section, key)
    local khist = khist()
    local t = khist[section]
    if type(t) == "table" then
        t = t[key]
        if type(t) == "table" then
            local sum = t.sum
            if type(sum) == "number" and sum > 0 then
                return sum
            end
        end
    end
end


function info()
    if not cache.info then
        local json = read_message("Fields[payload.info]")
        local ok
        ok, cache.info = pcall(cjson.decode, json)
        if not ok then cache.info = {} end
    end
    return cache.info
end


function hours()
    local uptime = info().subsessionLength
    if type(uptime) ~= "number" or uptime < 1 or uptime >= 180 * SEC_IN_DAY then
        return 0
    end
    return uptime / SEC_IN_HOUR
end


function payload()
    if not cache.payload then
        local json = read_message("Payload")
        local ok
        ok, cache.payload = pcall(cjson.decode, json)
        if not ok then cache.payload = {} end

        if type(cache.payload.payload) ~= "table" then
            cache.payload.payload = {}
        end
    end
    return cache.payload
end


function get_timestamp(d)
    if type(d) == "string" then
        local t = dt.rfc3339:match(d)
        if t then
            return dt.time_to_ns(t)
        else -- some dates are not RFC compliant
            t = crash_date:match(d)
            if t then
                return dt.time_to_ns(t)
            end
        end
    end
end


function get_date(d)
    if type(d) == "string" then
        local t = crash_date:match(d)
        if t then
            return format("%s-%s-%s", t.year, t.month, t.day)
        end
    end
end

return M

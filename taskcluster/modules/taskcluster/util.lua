-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Taskcluster Utility Module

## Functions

### get_time_t

Returns time_t from a standard Taskcluster timestamp

*Arguments*
- ts (string) Taskcluster timestamp

*Return*
- time_t (integer/nil) - Unix time_t or nil if ts is malformed

### get_time_m

Returns time_t of the base minute from a standard Taskcluster timestamp

*Arguments*
- ts (string) Taskcluster timestamp

*Return*
- time_m (integer/nil) - Unix time_t with the seconds stripped
- time_t (integer/nil) - Unix time_t or nil if ts is malformed


### normalize_workertype

Returns the normalized Taskcluster workertype

*Arguments*
- wt (string) Raw workerType

*Return*
- wt (string) - Normalize Taskcluster workerType

--]]

-- Imports
local os        = require "os"
local string    = require "string"

local type = type

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

function get_time_t(ts)
    if type(ts) ~= "string" then return nil end

    local time_t
    local t = {}
    t.year, t.month, t.day, t.hour, t.min, t.sec = ts:match("^(%d%d%d%d)-(%d%d)-(%d%d)[T ](%d%d):(%d%d):(%d%d)") -- allow space for BQ exported JSON to work
    if t.year then
        time_t = os.time(t)
    end
    return time_t
end


function get_time_m(ts)
    local time_t = get_time_t(ts)
    local time_m
    if time_t then time_m = time_t - (time_t % 60) end
    return time_m, time_t
end


function normalize_workertype(wt)
    if type(wt) ~= "string" then return "_" end

    if wt:match("^test%-.+%-a$") then
        wt = "test-generic"
    elseif wt:match("^dummy%-worker%-") then
        wt = "dummy-worker"
    elseif wt:match("^dummy%-type%-") then
        wt = "dummy-type"
    end
    return wt
end

return M

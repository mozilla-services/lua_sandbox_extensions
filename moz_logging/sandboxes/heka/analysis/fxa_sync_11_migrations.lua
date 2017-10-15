-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# FXA Sync 1.1 Migrations

Tracks the FXA Sync migration counts.

## Sample Configuration
```lua
filename = 'fxa_sync_11_migrations.lua'
message_matcher = "Type == 'logging.fxa.content_server.nginx.access' && Fields[request] =~ 'migration=sync11'"
ticker_interval = 60
preserve_data = true

-- rows = 365 -- number of rows in the graph data
-- sec_per_row = 60 * 60 * 24-- number of seconds each row represents
-- max_entries = 180
```
--]]
require "os"
require "cjson"
require "hyperloglog"
require "math"
require "table"
require "circular_buffer"

-- circular buffer
local rows         = read_config("rows") or 365
local sec_per_row  = read_config("sec_per_row") or 60 * 60 * 24
local title        = "Sync 1.1 Migrations"

total = circular_buffer.new(rows, 2, sec_per_row)
local SUCCESS = total:set_header(1, "SUCCESS")
local FAILURE = total:set_header(2, "FAILURE")

-- JSON output
local max_entries = read_config("max_entries") or 180

metrics = {
      total_sync_11_migrations      = 0
    , cumulative_sync_11_migrations = {}
    , new_sync_11_migrations        = {}
}

active_day = 0
n = 0

local sec_in_day = 60 * 60 * 24
local floor = math.floor

local function create_day(day, t, n)
    if #t == 0 or day > t[#t].time_t then -- only advance the day, gaps are ok but should not occur
        if #t == max_entries then
            table.remove(t, 1)
        end
        t[#t+1] = {time_t = day, date = os.date("%F", day), n = n}
        return #t
    end
    return nil
end

local function find_day(day, t)
    for i = #t, 1, -1 do
        local time_t = t[i].time_t
        if day > time_t then
            return nil
        elseif day == time_t then
            return i
        end
    end
end

local function set (t, w, field, v)
    local idx = find_day(w * sec_in_day, t)
    if not idx then
        idx = create_day(w * sec_in_day, t, 0)
    end
    t[idx][field] = v
end

local function pre_initialize()
    local t = os.time()
    t = t - (t % sec_in_day)
    for i = t - ((max_entries-1) * sec_in_day), t, sec_in_day do
        create_day(i, metrics.cumulative_sync_11_migrations, 0)
        create_day(i, metrics.new_sync_11_migrations, 0)
    end
end
pre_initialize()

function process_message ()
    local ts = read_message("Timestamp")
    local day = floor(ts / (sec_in_day * 1e9))

    if day < active_day  then
        return 0 -- too old
    elseif day > active_day then
        active_day = day
    end
    if read_message("Fields[status]") == 200 then
        metrics.total_sync_11_migrations = metrics.total_sync_11_migrations + 1
        total:add(ts, SUCCESS, 1)
        set(metrics.new_sync_11_migrations, active_day, "n", total:get(ts, SUCCESS))
        set(metrics.cumulative_sync_11_migrations, active_day, "n", metrics.total_sync_11_migrations)
    else
        total:add(ts, FAILURE, 1)
    end

    return 0
end

local function format (a)
    return cjson.encode(a)
end

function timer_event(ns)
    inject_payload("cbuf", title, total:format("cbuf"))
    for k,v in pairs(metrics) do
        inject_payload("json", "fxa_" .. k, cjson.encode({[k] = v}))
    end
end

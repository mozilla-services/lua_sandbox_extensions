-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Logging Active Counts

Generate REPORT_LENGTH-day counts at REPORT_INTERVAL-day intervals.

TODO dimensions, cbuf, partial updates## Sample Configuration

```lua
filename = 'moz_logging_active_counts.lua'
message_matcher = "Type == 'logging.fxa.auth_server.docker.fxa-auth|request.summary' && Fields[path] == '/v1/certificate/sign' && Fields[errno] == 0"
ticker_interval = 60
preserve_data = true

-- max_entries = 180
-- message_variable = "Fields[uid]" -- supports a comma delimited list of variables
-- report_interval = 1
-- report_length = 1
json_name = "fxa_dau" -- JSON payload name
```
--]]

require "os"
require "cjson"
require "hyperloglog"
require "math"
require "table"
local l = require "lpeg"
l.locale(l)

local sep = l.P","
local elem = l.C((1 - sep)^1)
local grammar = l.Ct(elem * (sep * elem)^0)

local max_entries = read_config("max_entries") or 180
local message_variables = grammar:match(read_config("message_variable") or "Fields[uid]")
local report_interval = read_config("report_interval") or 1
local report_length = read_config("report_length") or 1
local json_name = read_config("json_name") or error("missing json output name")
local offset = 1
local total = "n"

atu = {}
active_day = 0
n = 0

atu_hll = {}

local USERS = 1
local sec_in_day = 60 * 60 * 24
local sec_in_interval = sec_in_day * report_interval

local floor = math.floor

local function create_day(day, t, n)
    if #t == 0 or day > t[#t].time_t then -- only advance the day, gaps are ok but should not occur
        if #t == max_entries then
            table.remove(t, 1)
        end
        t[#t+1] = {time_t = day, date = os.date("%F", day), [total] = n}
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

function process_message ()
    local ts = read_message("Timestamp")
    local day = floor(ts / (sec_in_day * 1e9))

    if day < active_day  then
        return 0 -- too old
    elseif day > active_day then
        local delta = day - active_day

        if active_day == 0 then
            active_day = day - 1
            n = 0
            delta = 1
        end

        for i = 1, delta, 1 do
            active_day = active_day + 1
            if n == report_length then
                if #atu_hll > 0 then
                    local v = table.remove(atu_hll, 1)
                    set(atu, active_day - offset, total, v:count())
                end
                n = report_length - report_interval
            end

            if active_day % report_interval == 0 then
                atu_hll[#atu_hll + 1] = hyperloglog.new()
            end
            n = n + 1
        end
    end

    for i, m in ipairs(message_variables) do
        local z = 0
        local uid = read_message(m, nil, z)
        while uid do
            for i, h in ipairs(atu_hll) do h:add(uid) end
            z = z + 1
            uid = read_message(m, nil, z)
        end
    end

    return 0
end

local function format (a)
    return cjson.encode(a)
end

function timer_event(ns)
    inject_payload("json", json_name, format(atu))
end

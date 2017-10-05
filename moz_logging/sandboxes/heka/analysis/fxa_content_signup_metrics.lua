-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# FXA Content Signup Metrics

Tracks the types of signups.

## Sample Configuration
```lua
filename = ''fxa_content_signup_metrics.lua'.lua'
-- todo verify matcher
message_matcher = "Type == 'logging.fxa.content_server.docker.fxa-content' && Fields[service] == '<%= id %>"
ticker_interval = 60
preserve_data = true
```
--]]
require "circular_buffer"
require "cjson"
require "os"
require "string"
require "table"

local max_days = 180
local sec_in_day = 60 * 60 * 24

local title       = "Content Signup Metrics"
local rows        = 365
local sec_per_row = 60 * 60 * 24

local keys = {
      "content_signup_intent"
    , "content_signup_engage"
    , "content_signup_success"
}

metrics = {}
for i, key in ipairs(keys) do
    metrics[key] = {}
end

data = circular_buffer.new(rows, 3, sec_per_row)
local INTENT = data:set_header(1, "intent")
local ENGAGE = data:set_header(2, "engage")
local SUCCESS = data:set_header(3, "success")

local function create_day(day, t, n)
    if #t == 0 or day > t[#t].time_t then -- only advance the day, gaps are ok but should not occur
        if #t == max_days then
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

local function pre_initialize()
    local t = os.time()
    t = t - (t % sec_in_day)
    for i = t - ((max_days-1) * sec_in_day), t, sec_in_day do
        create_day(i, metrics.content_signup_intent, 0)
        create_day(i, metrics.content_signup_engage, 0)
        create_day(i, metrics.content_signup_success, 0)
    end
end
pre_initialize()

function process_message ()
    local ts = read_message("Timestamp")
    local i = 0
    local signup, signin, confirm, err = false, false, false, false
    local e = read_message("Fields[events]", 0, i)

    while e ~= nil do
        if e == "screen.signup" then
            signup = true
        elseif e == "screen.signin" then
            signin = true
        elseif e == "screen.confirm" then
            confirm = true
        elseif e:match("error") and not e:match("error.*1017") then
            -- 1017 is timeout, we don't want to count this as an error
            -- (if it's the only error)
            err = true
        end

        i = i + 1
        e = read_message("Fields[events]", 0, i)
    end
    -- "Intent to signup"
    if (signup and not signin) or (signup and confirm) then
        data:add(ts, INTENT, 1)
    end
    -- "Engage with signup"
    if (signup and confirm) or (signup and err and not signin) then
        data:add(ts, ENGAGE, 1)
    end
    -- "Signup success"
    if signup and confirm then
        data:add(ts, SUCCESS, 1)
    end

    return 0
end

local function update_json ()
    local cur_ns = data:current_time()
    local prev_ns = cur_ns - (sec_per_row * 1e9)

    for i,v in ipairs(keys) do
        local t = metrics[v]
        for j,k in ipairs({prev_ns, cur_ns}) do
            local n = data:get(k, i)
            if n ~= n then n = 0 end
            local idx = find_day(k / 1e9, t)
            if not idx then
                create_day(k / 1e9, t, n)
            else
                t[idx].n = n
            end
        end
    end

end

function timer_event(ns)
    update_json()
    inject_payload("cbuf", title, data)
    for k,v in pairs(metrics) do
        inject_payload("json", "fxa_" .. k, cjson.encode({[k] = v}))
    end
end

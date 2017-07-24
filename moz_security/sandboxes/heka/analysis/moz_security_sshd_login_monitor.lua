-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
#  Mozilla Security SSHD Login Monitor

## Sample Configuration
```lua
filename = "moz_security_sshd_login_monitor.lua"
message_matcher = "Logger == 'input.syslog' && Fields[programname] == 'sshd' && Fields[sshd_authmsg] == 'Accepted'"
ticker_interval = 0
process_message_inject_limit = 1

closed = {
    tz      = "America/Los_Angeles",
    days    = {"Sat", "Sun"},
    holidays = {
        "2017-09-04", -- Labor Day
        "2017-11-23", -- Thanksgiving Holiday
        "2017-11-24", -- Thanksgiving Holiday + 1
        "2017-12-25", -- Christmas Day
        "2017-12-26", -- Christmas + 1
        "2017-01-01", -- New Year's Day
        "2017-01-15", -- Martin Luther King, Jr. Day
        "2017-02-19", -- Presidents' Day
        "2017-05-28", -- Memorial Day
    },
    hours   = {open = "09:00", close = "17:00"},
}

alert = {
    prefix = true,
    throttle = 1,
    modules = {
        email = {recipients = {"pagerduty@mozilla.com"}}
    }
}

user_map = {
    trink = "mtrinkala"
}

```
--]]

require "date"
require "string"
require "table"
local alert = require "heka.alert"

local function get_hm(hm)
    assert(hm, "missing hours configuration")
    local h, m = string.match(hm, "(%d%d):(%d%d)") or error("invalid c.hours")
    return {hour = h, min = m}
end


local function load_cfg()
    local c = read_config("closed") or error("a closed table must be configured")
    c.user_map = read_config("user_map") or {}
    if not c.tz then c.tz = "UTC" end

    if c.hours then
        c.hours.open  = get_hm(c.hours.open)
        c.hours.close = get_hm(c.hours.close)
    end

    if c.days and #c.days > 0 then
        local t = {}
        for _, n in ipairs(c.days) do
            local found = false
            for i, v in ipairs({"Sun", "Mon", "Tue", "Wed", "Thr", "Fri", "Sat"}) do
                if n == v then
                    t[i] = v
                    found = true
                    break
                end
            end
            if not found then error("invalid c.day") end
        end
        c.days = t
    end

    if c.holidays then
        local tm = {}
        for i, v in ipairs(c.holidays) do
            local s = date.time(v, "%Y-%m-%d", c.tz)
            date.get(s, tm)
            tm.day = tm.day + 1
            local e = date.time(tm, c.tz)
            c.holidays[i] = {s, e}
        end
        table.sort(c.holidays, function(a,b) return a[1] < b[1] end)
    end
    return c
end


local tm = {}
local function is_closed(c, ns)
    date.get(ns, tm, c.tz)
    if c.days[tm.wday] then return true end
    tm.sec = 0
    tm.sec_frac = 0

    tm.hour = c.hours.open.hour
    tm.min  = c.hours.open.min
    local open = date.time(tm, c.tz)

    tm.hour = c.hours.close.hour
    tm.min  = c.hours.close.min
    local close = date.time(tm, c.tz)

    if ns >= close and ns < open then
        return true
    end

    for _, v in ipairs(c.holidays) do
        if ns >= v[1] and ns < v[2] then return true end
        if ns <= v[1] then break end
    end
    return false
end


local cfg = load_cfg()
function process_message()
    local ns = read_message("Timestamp")
    if is_closed(cfg, ns) then
        local ip   = read_message("Fields[remote_addr]")
        local user = read_message("Fields[remote_user]")
        local mu   = cfg.user_map[user]
        if mu then user = mu end

        alert.send("sshd", "ssh connection outside of business hours",
                   string.format("user: %s\nip: %s\n", user, ip), 0) -- disable throttling
    end
    return 0
end


function timer_event()
-- no op
end

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Security Simultaneous Usage, Tracking Variation

This plugin uses Heka selprinc to parse and normalize authentication or application
usage activity, and identifies scenarios where usage is seen from two different tracking
values within a fixed window of time.

The width configuration parameter can be used to specify the window size (in seconds) for which
events will be compared with each other. As an example, if an event is seen for tracked value
X, then tracked value Y, and then tracked value X again for the same user where the delta
between the third and second events is less than width, an alert will be generated.

The Timestamp field is used to determine the event timestamp and should be set appropriately
in the input plugin.

Suitable parameters for tracking include selprinc auxilliary values such as GeoIP country.

If enable_metrics is true, the module will submit metrics events for collection by the metrics
output sandbox. Ensure process_message_inject_limit is set appropriately, as if enabled process_event
will submit up to 2 messages (the alert, and the metric event).

## Sample Configuration
```lua
filename = "moz_security_simuse.lua"
message_matcher = "Type ~= 'mozphab'%"
ticker_interval = 0
process_message_inject_limit = 1

-- preserve the tracking data across process restarts
preserve_data = true
-- preservation_version = 0 -- optional, increment if config is changed

-- acceptable_message_drift = 1500 -- optional, default shown, 0 to disable
-- width = 21600 -- optional, inspection width default 21600 (6 hours)

selprinc_track = { "geocountry" }

heka_selprinc = {
    events = {
        ssh = {
            select_field     = "Fields[controller]",
            select_match     = ".+",
            subject_field    = "Fields[user]",
            object_field     = "Fields[controller]",
            sourceip_field   = "Fields[ip]",

            aux = {
                { "geocity", "Fields[ip_city]" },
                { "geocountry", "Fields[ip_country]" }
            }
        }
    }
}

-- enable_metrics = false -- optional, if true enable secmetrics submission
```
--]]

require "math"
require "string"
require "table"

local selprinc  = require "heka.selprinc"
local alert     = require "heka.alert"

local sm_track  = read_config("selprinc_track") or error("selprinc_track must be configured")
local width     = read_config("width") or 21600
local okdrift   = read_config("acceptable_message_drift") or 1500

local secm
if read_config("enable_metrics") then
    secm = require "heka.secmetrics".new()
end

_PRESERVATION_VERSION = read_config("preservation_version") or 0

userdata = {} -- global, reload on startup

function send_alert(user, cur, p, prev, interim)
    local summary = string.format("SIMUSE %s [%s/%d]->[%s/%d]->[%s/%d] %s?", user, cur.track, p.observed,
        prev.track, prev.observed, cur.track, cur.observed, prev.track)
    local payload = string.format("%s src %s (t - %ds) [%s]\n", p.dest, p.srcip, cur.observed - p.observed,
        cur.track)
    payload = payload .. string.format("%s src %s (t - %ds) [%s]\n", prev.dest, prev.srcip,
        cur.observed - prev.observed, prev.track)
    payload = payload .. string.format("%s src %s (t=%d) [%s]\n", cur.dest, cur.srcip, cur.observed,
        cur.track)

    if #interim > 0 then
        payload = payload .. "\n"
        for i,v in ipairs(interim) do
            payload = payload .. string.format("interim: %s src %s (t - %ds) [%s]\n", v.dest, v.srcip,
                cur.observed - v.observed, v.track)
        end
    end

    alert.send(summary, summary, payload)
end

local function userdata_init(user)
    local ret = userdata[user]
    if not ret then
        ret = { count = 0, entries = {} }
        userdata[user] = ret
    end
    return ret
end

function userdata_most_recent(ud)
    local max = 0
    local ret = nil
    for k,v in pairs(ud.entries) do
        if v.observed > max then
            max = v.observed
            ret = k
        end
    end
    return ret
end

local function userdata_interim_suppress(ud, cur, prev)
    local ret = {}
    for k,v in pairs(ud.entries) do
        if k ~= cur.track and k ~= prev.track and not v.suppressed then
            local d = cur.observed - v.observed
            if d >= 0 and d <= width then
                v.suppressed = true
                table.insert(ret, v)
            end
        end
    end
    return ret
end

local function userdata_purge_old(ud, ts)
    for k,v in pairs(ud.entries) do
        if ts - v.observed > width or v.suppressed then
            ud.entries[k] = nil
            ud.count = ud.count - 1
        end
    end
end

local function userdata_new(ud, sm, ts, track)
    ud.entries[track] = {
        srcip       = sm.sourceip,
        dest        = sm.object,
        count       = 1,
        observed    = ts,
        track       = track
    }
    ud.count = ud.count + 1
end

local function userdata_suppress(ud, track)
    ud.entries[track].suppressed = true
end

function process_message()
    local sm = selprinc.match()
    if not sm then return 0 end -- nothing in the selprinc cfg matched, ignore

    local ts = math.floor(read_message("Timestamp") / 1e9)
    local delaysec = math.abs(os.time() - ts)
    if okdrift ~= 0 and delaysec > okdrift then
        return -1, "ignoring event with unacceptable timestamp drift"
    end

    local track
    for i,v in ipairs(sm_track) do
        local buf = sm[v]
        if not buf then return -1, "event did not contain required tracking field" end
        if track then
            track = string.format("%s+%s", track, buf)
        else
            track = buf
        end
    end

    local user  = sm.subject
    local ud    = userdata_init(user)
    if ud.count > 0 then userdata_purge_old(ud, ts) end

    local entry = ud.entries[track]
    if not entry then
        userdata_new(ud, sm, ts, track)
        return 0
    end

    local isrecent = userdata_most_recent(ud) == track

    local pparam = {
        observed    = entry.observed,
        dest        = entry.dest,
        srcip       = entry.srcip
    }

    entry.observed   = ts
    entry.dest       = sm.object
    entry.srcip      = sm.sourceip
    entry.count      = entry.count + 1

    if isrecent then return 0 end

    local sentalert = false
    for k,v in pairs(ud.entries) do
        if k ~= track then
            local d = entry.observed - v.observed
            if d >= 0 and d <= width then
                userdata_suppress(ud, k)
                send_alert(user, entry, pparam, v, userdata_interim_suppress(ud, entry, v))
                sentalert = true

                if secm then
                    secm:inc_accumulator("alert_count")
                    secm:add_uniqitem("unique_users", user)
                    secm:send()
                end
            end
        end
        if sentalert then break end
    end

    return 0
end

function timer_event()
    -- no op
end

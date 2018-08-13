-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Security Authentication Events, Last X attribute(s) tracking by user

This module can be used to generate alerts if an authentication event is seen for a user
that has new properties or attributes. In this context, a new attribute may be a field
such as a source IP address, a new geo-location, or any combination of values returned
in the selprinc match.

The module makes use of the Heka selprinc module for event matching and normalization, and
requires a valid selprinc configuration to be present to indicate which events to consider
as authentication events, and which fields to translate.

To use geocity and geocountry information in alerting, this plugin expects a valid aux configuration
in selprinc storing the geocity and geocountry values in the keys "geocity" and "geocountry" in
the returned selprinc match. If used, this is not required to be present for every event
category but for any that has these fields available the plugin will incorporate the information
into alerting.

Multiple elements in selprinc are supported such that a single tracking database can be
applied to more than one event type. This assumes that the username/subject field will be
consistent across the event types you want to compare.

If the username is not consistent across event types, subject_map can be used for a given
event type to map values to the desired string.

selprinc_track specifies which element or combination of elements in the returned selprinc
match you want to compare to identify new attributes. If more than one element is specified,
the values are concatenated together prior to comparison with previous authentication events.

The module always generates an alert for an applicable message, but if an event is seen that has
new data that isn't included in the tracked data the alert is modified to indicate this.

The lastx configuration value controls the number of previous attributes that are tracked for
a given user ID. By default lastx is 5.

This module uses custom alerting integration in order to modify the recipient address, and supports
email and IRC based alert generating for the alert output module.

If default_email is set, email based alerting is enabled and this recipient always receives a copy
of the alert message. If the message has new tracking data, user_recip also recieves a copy of the
alert message. If the message has unacceptable time drift, drift_email only receives a copy of the
message.

If default_irc is set, IRC channel output will occur at the specified target. See the heka IRC
alerting modules for more infomation on this output mode.

If enable_metrics is true, the module will submit metrics events for collection by the metrics
output sandbox. Ensure process_message_inject_limit is set appropriately, as if enabled process_event
will submit up to 2 messages (the alert, and the metric event).

## Sample Configuration
```lua
filename = "moz_security_auth_lastx.lua"
message_matcher = "Type ~= 'bastion.file.sshd'% && Fields[sshd_authmsg] == 'Accepted'"
ticker_interval = 0
process_message_inject_limit = 1

-- preserve the tracking data across process restarts
preserve_data = true
-- preservation_version = 0 -- optional, increment if config is changed

default_email = "foxsec-dump+OutOfHours@mozilla.com" -- optional, enable email alerting
-- default_irc = "irc.server#channel" -- optional, enable IRC alerting
-- user_email = "manatee-%s@moz-svc-ops.pagerduty.com" -- optional user specific email address
-- drift_email = "captainkirk@mozilla.com" -- optional drift message notification
-- acceptable_message_drift = 600 -- optional, defaults to 600 seconds if not specified

-- expireolderthan = 864000 -- optional, tracked entries older than value are removed, defaults to 864000
-- lastx = 5 -- optional, track last X entries, defaults to 5

selprinc_track = { "sourceip" }

heka_selprinc = {
    events = {
        ssh = {
            select_field     = "Fields[programname]",
            select_match     = "^sshd$",
            subject_field    = "Fields[user]",
            object_field     = "Hostname",
            sourceip_field   = "Fields[ssh_remote_ipaddr]",

            aux = {
                { "geocity", "Fields[ssh_remote_ipaddr_city]" },
                { "geocountry", "Fields[ssh_remote_ipaddr_country]" }
            }
        },
        awsconsole = {
            select_field     = "Fields[eventType]",
            select_match     = "^AwsConsoleSignIn$",
            subject_field    = "Fields[userIdentity.userName]",
            object_field     = "Fields[recipientAccountId]",
            sourceip_field   = "Fields[sourceIPAddress]"
        },
        duopull = {
            select_field     = "Fields[msg]",
            select_match     = "^duopull event$",
            subject_field    = "Fields[event_username]",
            object_field     = "Fields[event_action]",
            sourceip_field   = "Fields[event_description_ip_address]",
            subject_map = {
                ["An admin user"]   = "admin",
                ["Commander Riker"] = "riker"
            }
        }
    }
}

-- enable_metrics = false -- optional, if true enable secmetrics submission
```
--]]
--

require "string"
require "math"
require "os"
require "table"

local HUGE      = require "math".huge
local selprinc  = require "heka.selprinc"

local default_email             = read_config("default_email")
local default_irc               = read_config("default_irc")
local user_email                = read_config("user_email")
local drift_email               = read_config("drift_email")
local acceptable_message_drift  = read_config("acceptable_message_drift") or 600
local lastx                     = read_config("lastx") or 5

local secm
if read_config("enable_metrics") then
    secm = require "heka.secmetrics".new()
end

local cephost           = read_config("Hostname") or "unknown"
local expireolderthan   = read_config("expireolderthan") or 864000
local sm_track          = read_config("selprinc_track") or error("selprinc_track must be configured")

_PRESERVATION_VERSION = read_config("preservation_version") or 0

-- global, we want to serialize this to reload on startup
userdata = {}


function get_msg(subject, defrecip, userrecip, defirc, payload)
    local msg = {
        Type = "alert",
        Payload = payload,
        Severity = 1,
        Fields = {
            { name = "id", value = "auth_lastx" },
            { name = "summary", value = subject },
        }
    }
    local i = 3
    if defrecip then
        if userrecip then
            msg.Fields[i] = {name = "email.recipients", value = {defrecip, userrecip}}
        else
            msg.Fields[i] = {name = "email.recipients", value = {defrecip}}
        end
        i = i + 1
    end
    if defirc then
        msg.Fields[i] = {name = "irc.target", value = defirc}
    end
    return msg
end


function prune_userdata(user, cutoff)
    if not userdata[user] then return 0 end
    local ret = 0
    for i=#userdata[user],1,-1 do
        if userdata[user][i][2] <= cutoff then
            table.remove(userdata[user], i)
            ret = ret + 1
        end
    end
    return ret
end


function process_message()
    local sm = selprinc.match()
    if not sm then return 0 end -- nothing in the selprinc cfg matched, ignore

    local ts            = math.floor(read_message("Timestamp") / 1e9)
    local hn            = sm.object or "unknown"
    local geocity       = sm.geocity
    local geocountry    = sm.geocountry
    local user          = sm.subject
    local sourceip      = sm.sourceip
    local track         = nil

    for i,v in ipairs(sm_track) do
        local buf = sm[v]
        if not buf then return -1, "event did not contain required tracking field" end
        if track then
            track = string.format("%s+%s", track, buf)
        else
            track = buf
        end
    end

    local delaysec = math.abs(os.time() - ts)
    local invalidts = false
    if delaysec > acceptable_message_drift then invalidts = true end

    local escalate = false
    if not invalidts then
        local userdatalen = 0
        if userdata[user] then userdatalen = #userdata[user] end
        if userdatalen > 0 then
            assert(userdatalen <= lastx)
            userdatalen = userdatalen - prune_userdata(user, os.time() - expireolderthan)
            local found = false
            local min = HUGE
            local rem = nil
            for i,v in ipairs(userdata[user]) do
                -- even if we find it early, iterate over the entire table to also locate
                -- the minimum ts
                if v[1] == track then
                    v[2] = ts
                    found = true
                end
                if v[2] < min then
                    min = v[2]
                    rem = i
                end
            end
            if not found then
                escalate = true
                if userdatalen == lastx then
                    table.remove(userdata[user], rem)
                else
                    userdatalen = userdatalen + 1
                end
                userdata[user][userdatalen] = { track, ts }
            end
        else
            escalate = true
            userdata[user] = {{ track, ts }}
        end
    end

    -- At this point, we know if the event should be escalated or not. First, update
    -- the alert message with the default information.
    local subject = string.format("%s %s auth %s track:[%s]", user, sm.category, hn, track)
    local defrecip = nil
    local userrecip = nil
    local payload = ""
    if default_email then defrecip = string.format("<%s>", default_email) end

    -- If we also have city and country information, add that to the subject
    if geocity and geocountry then
        subject = subject .. string.format(" (%s, %s)", geocity, geocountry)
    end

    -- If escalate is set, add some additional information to the message
    if escalate then
        subject = "LASTX_NEWATTR " .. subject
        payload = "Escalation flag set, authentication with new tracking attributes\n"
        if user_email and defrecip then
            userrecip = string.format(string.format("<%s>", user_email), user)
        end
    end

    -- Add some additional details to the message body
    payload = payload .. string.format("Generated by %s, event timestamp %s\n",
        cephost, os.date("%Y-%m-%d %H:%M:%S", ts))

    -- Finally, if the message has time drift modify the recipient address and add some additional
    -- information to the payload
    if invalidts then
        if not drift_email then return -1, "dropping event with time drift" end
        if defrecip then
            defrecip = string.format("<%s>", drift_email)
            userrecip = nil
        end
        payload = payload .. string.format("WARNING, unacceptable drift %d seconds\n", delaysec)
    end

    if secm then
        secm:inc_accumulator("total_count")
        if escalate then secm:inc_accumulator("alert_count") end
        if invalidts then secm:inc_accumulator("invalidts_count") end
        secm:add_uniqitem("unique_users", user)
        secm:add_uniqitem("unique_sources", track)
        secm:send()
    end

    inject_message(get_msg(subject, defrecip, userrecip, default_irc, payload))
    return 0
end


function timer_event()
    -- no op
end

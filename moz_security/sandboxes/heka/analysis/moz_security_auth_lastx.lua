-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Security Authentication Events, Last X attribute(s) tracking by user

This module can be used to generate alerts if an authentication event is seen for a user
that has new properties or attributes. In this context, a new attribute may be a field
such as a source IP address, a new geo-location, or any combination of fields present
in the message.

For messages matching the matcher, the field indicated by user_field is extracted to identify
the user ID associated with the event. track_fields are then extracted, and concatenated
together in the order they are specified in the configuration. This value is then compared against
the last events seen for the user, and if the tracked value is new an alert is submitted to user_email.

The lastx configuration value controls the number of previous attributes that are tracked for
a given user ID. By default lastx is 5.

default_email always receives a notification of the authentication event, even if the track_fields
values are known. If user_email is nil then the default_email recipient only recieves the message.

If the message timestamp falls outside acceptable_message_drift, only drift_email recieves a notice
of the alert. If drift_email is nil no alert is submitted.

## Sample Configuration
```lua
filename = "moz_security_auth_lastx.lua"
message_matcher = "Type ~= 'bastion.file.sshd'% && Fields[sshd_authmsg] == 'Accepted'"
ticker_interval = 0
process_message_inject_limit = 1

default_email = "foxsec-dump+OutOfHours@mozilla.com" -- required
-- user_email = "manatee-%s@moz-svc-ops.pagerduty.com" -- optional user specific email address
-- drift_email = "captainkirk@mozilla.com" -- optional drift message notification
-- acceptable_message_drift = 600 -- optional, defaults to 600 seconds if not specified

authhost_field = "Hostname" -- required, field to extract authenticating host from (destination host)
user_field = "Fields[user]" -- required, field to extract username from
track_fields = { "Fields[ssh_remote_ipaddr]" } -- required, fields to extract tracking data from
-- track_fields = { "Fields[ssh_remote_ipaddr_city]", "Fields[ssh_remote_ipaddr_country]" }

-- The geocity_field and geocountry_field values are optional, but if set and they are included
-- with the message and will be appended to the alert text as additional informational data
geocity_field = "Fields[ssh_remote_ipaddr_city"] -- optional, field to extract geo city
geocountry_field = "Fields[ssh_remote_ipaddr_country"] -- optional, field to extract geo country
```
--]]
--

require "string"
require "math"
require "os"
require "table"

local iputils   = require "iputils"
local HUGE      = require "math".huge

local default_email             = read_config("default_email") or error("default_email must be configured")
local user_email                = read_config("user_email")
local drift_email               = read_config("drift_email")
local acceptable_message_drift  = read_config("acceptable_message_drift") or 600
local lastx                     = read_config("lastx") or 5

local authhost_field    = read_config("authhost_field") or error("authhost_field must be configured")
local user_field        = read_config("user_field") or error("user_field must be configured")
local track_fields      = read_config("track_fields") or error("track_fields must be configured")
local geocity_field     = read_config("geocity_field")
local geocountry_field  = read_config("geocountry_field")
local cephost           = read_config("Hostname") or "unknown"

-- global, we want to serialize this to reload on startup
userdata = {}

local msg = {
    Type = "alert",
    Payload = "",
    Severity = 1,
    Fields = {
        { name = "id", value = "auth_lastx" },
        { name = "summary", value = "" },
        { name = "email.recipients", value = {}}
    }
}


function process_message()
    local ts            = math.floor(read_message("Timestamp") / 1e9)
    local hn            = read_message(authhost_field) or "unknown"
    local geocity       = read_message(geocity_field)
    local geocountry    = read_message(geocountry_field)
    local user          = read_message(user_field)
    local track         = nil
    if not user then
        return -1, "message was missing required user field"
    end
    for i,v in ipairs(track_fields) do
        local buf = read_message(v)
        if not buf then return -1, "message was missing a required tracking field" end
        if track then
            track = string.format("%s+%s", track, buf)
        else
            track = buf
        end
    end

    local escalate = false
    local userdatalen = 0
    if userdata.user then userdatalen = #userdata.user end
    if userdatalen > 0 then
        local found = false
        local min = HUGE
        local rem = nil
        for i,v in ipairs(userdata.user) do
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
            if userdatalen >= lastx then
                table.remove(userdata.user, rem)
            end
            table.insert(userdata.user, 1, { track, ts })
        end
    else
        userdata.user = {{ track, ts }}
    end

    -- At this point, we know if the event should be escalated or not. First, update
    -- the alert message with the default information since we always send there.
    msg.Fields[2].value = string.format("%s authentication %s track:[%s]", user, hn, track)
    msg.Fields[3].value[1] = string.format("<%s>", default_email)
    msg.Fields[3].value[2] = nil
    msg.Payload = ""

    -- If we also have city and country information, add that to the subject
    if geocity and geocountry then
        msg.Fields[2].value = msg.Fields[2].value .. string.format(" (%s, %s)", geocity, geocountry)
    end

    -- If escalate is set, add some additional information to the message
    if escalate then
        msg.Fields[2].value = "LASTX_NEWATTR " .. msg.Fields[2].value
        if user_email then
            msg.Fields[3].value[2] = string.format(string.format("<%s>", user_email), user)
        end
        msg.Payload = "Escalation flag set, authentication with new tracking attributes\n"
    end

    -- Add some additional details to the message body
    msg.Payload = msg.Payload .. string.format("Generated by %s, event timestamp %s\n",
        cephost, os.date("%Y-%m-%d %H:%M:%S", tss))

    -- Finally, if the message has time drift modify the recipient address and add some additional
    -- information to the payload
    local delaysec = math.abs(os.time() - ts)
    if delaysec > acceptable_message_drift then
        if not drift_email then return -1, "dropping event with time drift" end
        msg.Fields[3].value[1] = string.format("<%s>", drift_email)
        msg.Fields[3].value[2] = nil
        msg.Payload = msg.Payload .. string.format("WARNING, unacceptable drift %d seconds\n", delaysec)
    end

    inject_message(msg)
    return 0
end


function timer_event()
    -- no op
end

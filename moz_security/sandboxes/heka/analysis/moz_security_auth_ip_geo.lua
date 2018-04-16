-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Security Authentication Events with IP and Geo-IP exclusion

For any messages matching the matcher, extract fields from the message and compare
these fields against expected origin IP or origin Geo-IP configuration for a given user.

This module makes use of a user specification table, which is a configured list of
known locations a given user will authenticate from. Locations can be specified as either
IP subnets, or Geo-IP configurations of the form "City/Country Code".

For each event recieved, an alert is always generated that sends a message to the
email address in default_email.

If the event also deviates from the user specification, the alert also submits an
email to user_email. If the message has a time drift outside of the configured parameters,
the message is only submitted to the drift_email recipient.

## Sample Configuration
```lua
filename = "moz_security_auth_ip_geo.lua"
message_matcher = "Type ~= 'bastion.file.sshd'% && Fields[sshd_authmsg] == 'Accepted'"
ticker_interval = 0
process_message_inject_limit = 1

default_email = "foxsec-dump+OutOfHours@mozilla.com" -- required
-- user_email = "manatee-%s@moz-svc-ops.pagerduty.com" -- optional user specific email address
-- drift_email = "captainkirk@mozilla.com" -- optional drift message notification
-- acceptable_message_drift = 600 -- optional, defaults to 600 seconds if not specified

authhost_field = "Hostname" -- required, field to extract authenticating host from (destination host)
user_field = "Fields[user]" -- required, field to extract username from
srcip_field = "Fields[ssh_remote_ipaddr]" -- required, field to extract source IP from
geocity_field = "Fields[ssh_remote_ipaddr_city"] -- required, field to extract geo city
geocountry_field = "Fields[ssh_remote_ipaddr_country"] -- required, field to extract geo country
```
--]]
--
require "string"
require "math"
require "os"
iputils = require "iputils"


local default_email             = read_config("default_email") or error("default_email must be configured")
local user_email                = read_config("user_email")
local drift_email               = read_config("drift_email")
local acceptable_message_drift  = read_config("acceptable_message_drift") or 600

local authhost_field    = read_config("authhost_field") or error("authhost_field must be configured")
local user_field        = read_config("user_field") or error("user_field must be configured")
local srcip_field       = read_config("srcip_field") or error("srcip_field must be configured")
local geocity_field     = read_config("geocity_field") or error("geocity_field must be configured")
local geocountry_field  = read_config("geocountry_field") or error("geocountry_field must be configured")
local cephost           = read_config("Hostname") or "unknown"
local userspec          = read_config("userspec") or error("userspec must be configured")


local msg = {
    Type = "alert",
    Payload = "",
    Severity = 1,
    Fields = {
        { name = "id", value = "auth_ip_geo" },
        { name = "summary", value = "" },
        { name = "email.recipients", value = {}}
    }
}


function check_ip(srcip, spec)
    if not spec.ip then return false end

    subnets = iputils.parse_cidrs(spec.ip)
    if not subnets then return false end
    return iputils.ip_in_cidrs(srcip, subnets)
end


function check_geo(city, country, spec)
    if not spec.geo then return false end
    if type(city) ~= "string" or type(country) ~= "string" then return false end

    for _,v in ipairs(spec.geo) do
        -- Within the spec the geo entries should be stored in
        -- city/country format, split out each entry
        local p = string.find(v, "/", 1, true)
        if not p then return false end
        local cityval = string.sub(v, 1, p-1)
        local countryval = string.sub(v, p+1, -1)
        if city == cityval and country == countryval then
            return true
        end
    end
    return false
end


function process_message()
    local ts = math.floor(read_message("Timestamp") / 1e9)
    local hn = read_message(authhost_field) or "unknown"

    local user = read_message(user_field)
    local srcip = read_message(srcip_field)
    if not user or not srcip then
        return -1, "message was missing a required field"
    end

    local geocity = read_message(geocity_field)
    local geocountry = read_message(geocountry_field)

    local spec = userspec[user]

    local escalate = false
    if spec then
        local ipok = check_ip(srcip, spec)
        if not ipok then
            local geook = check_geo(geocity, geocountry, spec)
            if not geook then escalate = true end
        end
    end

    -- At this point, we know if the event should be escalated or not. First, update
    -- the alert message with the default information since we always send there.
    msg.Fields[2].value = string.format("%s authentication %s from %s", user, hn, srcip)
    msg.Fields[3].value[1] = string.format("<%s>", default_email)
    msg.Fields[3].value[2] = nil
    msg.Payload = ""

    -- If we also have city and country information, add that to the subject
    if geocity and geocountry then
        msg.Fields[2].value = msg.Fields[2].value .. string.format(" (%s, %s)", geocity, geocountry)
    end

    -- If escalate is set, add some additional information to the message
    if escalate then
        msg.Fields[2].value = "ANOMALY " .. msg.Fields[2].value
        if user_email then
            msg.Fields[3].value[2] = string.format(string.format("<%s>", user_email), user)
        end
        msg.Payload = "Escalation flag set, authentication source does not match user specification\n"
    elseif not spec then
        msg.Fields[2].value = "NOSPEC " .. msg.Fields[2].value
        msg.Payload = "No user specification present for comparison against authentication\n"
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

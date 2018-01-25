-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
#  Mozilla Security SSHD Login Monitor

Sends a message to Pagerduty anytime there is a successful Bastion sshd login.
Pagerduty will then alert if it is out of policy (hours) for that user.

## Sample Configuration
```lua
filename = "moz_security_sshd_login_monitor.lua"
message_matcher = "Type == 'logging.shared.bastion.systemd.sshd' && Fields[sshd_authmsg] == 'Accepted'"
ticker_interval = 0
process_message_inject_limit = 1

-- default_email = "foxsec-dump+OutOfHours@mozilla.com"
```
--]]
require "string"

local default_email = read_config("default_email") or "foxsec-dump+OutOfHours@mozilla.com"
local msg = {
    Type = "alert",
    Payload = "",
    Severity = 1,
    Fields = {
        {name = "id"                , value = "sshd"},
        {name = "summary"           , value = ""},
        {name = "email.recipients"  , value = {string.format("<%s>", default_email)}}
    }
}

function process_message()
    local user    = read_message("Fields[user]")
    local ip      = read_message("Fields[ssh_remote_ipaddr]")
    local city    = read_message("Fields[ssh_remote_ipaddr_city]")
    local country = read_message("Fields[ssh_remote_ipaddr_country]")

    msg.Fields[2].value    = string.format("%s logged into bastion from %s", user, ip)
    -- If we also have city and country information, append that to the message
    if city and country then
        msg.Fields[2].value = msg.Fields[2].value .. string.format(" (%s, %s)", city, country)
    end
    msg.Fields[3].value[2] = string.format("<manatee-%s@moz-svc-ops.pagerduty.com>", user)
    inject_message(msg)
    return 0
end


function timer_event()
-- no op
end

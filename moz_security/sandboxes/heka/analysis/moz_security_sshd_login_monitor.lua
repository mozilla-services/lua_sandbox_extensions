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

user_map = {
    foobar = "foobar@pagerduty.com",
    -- ["*"]     = "user_map_maintainer@pagerduty.com" -- catch all
}

```
--]]
require "string"

local user_map = read_config("user_map") or error("user_map must be set")
for k,v in pairs(user_map) do
    user_map[k] = string.format("<%s>", v)
end

local default = user_map["*"]
if default then
    local mt = {__index = function(t, k) return default end }
    setmetatable(user_map, mt);
end

local msg = {
    Type = "alert",
    Payload = "",
    Severity = 1,
    Fields = {
        id                      = "sshd",
        summary                 = "",
        ["email.recipients"]    = ""
    }
}

function process_message()
    local ip    = read_message("Fields[remote_addr]")
    local user  = read_message("Fields[remote_user]")
    local email = user_map[user]
    if not email then return -1, "no user mapping specified" end

    msg.Fields.summary = string.format("%s logged into bastion from %s", user, ip)
    msg.Fields["email.recipients"] = email
    inject_message(msg)
    return 0
end


function timer_event()
-- no op
end

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Generates sample authentication events for auth_lastx

--]]

require "os"
require "string"

local sdec = require "decoders.syslog"
local cdec = require "decoders.moz_logging.json_heka"

-- test table, array indices correspond to analysis and output configurations
local test = {
    {
        { "sshd", "Accepted publickey for riker from 192.168.1.2 port 4242 ssh2", sdec, 0 },
        { "sshd", "Accepted publickey for riker from 192.168.1.2 port 4242 ssh2", sdec, 0 },
        { "dontmatchme", "Accepted publickey for riker from 10.10.10.10 port 4242 ssh2", sdec, 0 },
        { nil, '{"EnvVersion":"2.0","Fields":{"event_action":"admin_login",' ..
            '"event_description_factor":"sms","event_description_device":"000-000-0000",' ..
            '"event_description_primary_auth_method": "Password",' ..
            '"event_description_ip_address": "10.0.0.1",' ..
            '"event_object":null,"event_timestamp":1530628619,"event_username":"Commander Riker",' ..
            '"msg":"duopull event","path":"/admin/v1/logs/administrator"},' ..
            '"Hostname":"test","Logger":"duopull","Pid":63207,"Severity":6,' ..
            '"Type":"app.log"}', cdec, 0 },
        { "sshd", "Accepted publickey for riker from 10.0.0.1 port 4242 ssh2", sdec, 0 },
    }
}

-- default message headers
local msg = {
    Timestamp = nil,
    Logger = nil,
    Hostname = "bastion.host"
}

function process_message()
    for i,v in ipairs(test) do
        msg.Logger = string.format("generate_auth_duo_%d", i)
        for _,w in ipairs(v) do
            local t = os.time() + w[4]
            if w[1] then -- treat as syslog
                local d = os.date("%b %d %H:%M:%S", t)
                w[3].decode(string.format("%s %s %s: %s", d, msg.Hostname, w[1], w[2]), msg, false)
            else -- treat as duo json data
                w[3].decode(w[2], msg)
            end
        end
    end
    return 0
end

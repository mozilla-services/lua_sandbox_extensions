-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Generates sample authentication events for auth_ip_geo

--]]

require "os"
require "string"

local sdec = require "decoders.syslog"

-- test table, array indices correspond to analysis and output configurations
local test = {
    {
        { "sshd", "Accepted publickey for riker from 192.168.1.2 port 4242 ssh2", sdec, 0 },
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 0 },
        { "sshd", "Accepted publickey for worf from 216.160.83.56 port 4242 ssh2", sdec, 0 },
        { "sshd", "Accepted publickey for picard from 10.0.0.10 port 4242 ssh2", sdec, 0 },
        { "sshd", "Accepted publickey for picard from 216.160.83.56 port 4242 ssh2", sdec, 0 }
    },
    {
        { "sshd", "Accepted publickey for riker from 192.168.1.2 port 4242 ssh2", sdec, 0 },
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, -1000 },
        { "sshd", "Accepted publickey for worf from 216.160.83.56 port 4242 ssh2", sdec, 1000 },
    },
    {
        { "sshd", "Accepted publickey for riker from 10.0.0.1 port 4242 ssh2", sdec, 0 },
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 0 },
        { "sshd", "Accepted publickey for troi from 192.168.1.2 port 4242 ssh2", sdec, 0 },
        { "sshd", "Accepted publickey for troi from 10.0.0.1 port 4242 ssh2", sdec, 0 },
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
        msg.Logger = string.format("generate_auth_%d", i)
        for _,w in ipairs(v) do
            local t = os.time() + w[4]
            local d = os.date("%b %d %H:%M:%S", t)
            w[3].decode(string.format("%s %s %s: %s", d, msg.Hostname, w[1], w[2]), msg, false)
        end
    end
    return 0
end

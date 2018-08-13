-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "os"
require "string"

local sdec = require "decoders.syslog"

local test = {
    {
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 0 },
        { "sshd", "Accepted publickey for riker from 81.2.69.192 port 4242 ssh2", sdec, 1 },
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 2 },
        { "sshd", "Accepted publickey for picard from 216.160.83.56 port 4242 ssh2", sdec, 0 },
        { "sshd", "Accepted publickey for picard from 216.160.83.56 port 4242 ssh2", sdec, 1 },
        { "sshd", "Accepted publickey for picard from 216.160.83.56 port 4242 ssh2", sdec, 2 },
        { "sshd", "Accepted publickey for picard from 216.160.83.56 port 4242 ssh2", sdec, 3 },
        { "sshd", "Accepted publickey for picard from 216.160.83.56 port 4242 ssh2", sdec, 4 },
        { "sshd", "Accepted publickey for picard from 216.160.83.56 port 4242 ssh2", sdec, 5 },
        { "sshd", "Accepted publickey for picard from 81.2.69.192 port 4242 ssh2", sdec, 30000 },
        { "sshd", "Accepted publickey for picard from 81.2.69.192 port 4242 ssh2", sdec, 30001 },
        { "sshd", "Accepted publickey for picard from 81.2.69.192 port 4242 ssh2", sdec, 30002 },
        { "sshd", "Accepted publickey for picard from 81.2.69.192 port 4242 ssh2", sdec, 30003 },
        { "sshd", "Accepted publickey for picard from 81.2.69.192 port 4242 ssh2", sdec, 30004 },
        { "sshd", "Accepted publickey for picard from 216.160.83.56 port 4242 ssh2", sdec, 50000 }
    },
    {
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 0 },
        { "sshd", "Accepted publickey for riker from 81.2.69.192 port 4242 ssh2", sdec, 60 },
        { "sshd", "Accepted publickey for riker from 81.2.69.192 port 4242 ssh2", sdec, 600 },
        { "sshd", "Accepted publickey for riker from 81.2.69.192 port 4242 ssh2", sdec, 601 },
        { "sshd", "Accepted publickey for riker from 81.2.69.192 port 4242 ssh2", sdec, 602 },
        { "sshd", "Accepted publickey for riker from 81.2.69.192 port 4242 ssh2", sdec, 650 },
        { "sshd", "Accepted publickey for riker from 81.2.69.192 port 4242 ssh2", sdec, 700 },
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 2000 },
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 2001 },
        { "sshd", "Accepted publickey for riker from 81.2.69.192 port 4242 ssh2", sdec, 2500 },
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 32000 },
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 32001 },
        { "sshd", "Accepted publickey for riker from 81.2.69.192 port 4242 ssh2", sdec, 33000 },
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 33001 }
    },
    {
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 0 },
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 1 },
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 2 },
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 3 },
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 3 },
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 50 },
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 55 },
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 100 },
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 200 },
        { "sshd", "Accepted publickey for riker from 89.160.20.128 port 4242 ssh2", sdec, 300 },
        { "sshd", "Accepted publickey for riker from 89.160.20.128 port 4242 ssh2", sdec, 301 },
        { "sshd", "Accepted publickey for riker from 89.160.20.128 port 4242 ssh2", sdec, 302 },
        { "sshd", "Accepted publickey for riker from 81.2.69.192 port 4242 ssh2", sdec, 400 },
        { "sshd", "Accepted publickey for riker from 81.2.69.192 port 4242 ssh2", sdec, 401 },
        { "sshd", "Accepted publickey for riker from 81.2.69.192 port 4242 ssh2", sdec, 402 },
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 1000 },
        { "sshd", "Accepted publickey for riker from 216.160.83.56 port 4242 ssh2", sdec, 1001 }
    },
}

local msg = {
    Timestamp   = nil,
    Logger      = nil,
    Hostname    = "bastion.host"
}

function process_message()
    for i,v in ipairs(test) do
        msg.Logger = string.format("test_%d", i)
        for _,w in ipairs(v) do
            local t = os.time() + w[4]
            local d = os.date("%b %d %H:%M:%S", t)
            w[3].decode(string.format("%s %s %s: %s", d, msg.Hostname, w[1], w[2]), msg, false)
        end
    end
    return 0
end

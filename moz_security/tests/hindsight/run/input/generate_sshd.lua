-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Generates test data for moz_security_sshd_login_monitor

--]]

require "os"

-- test table, array indices correspond to analysis and output configurations
local tests = {
    {
        {"11111111-1111-1111-1111-111111111111", "trink", "192.168.1.1", nil},
        {"11111111-1111-1111-1111-111111111112", "trink", "192.168.1.2", nil}
    },
    {
        {"11111111-1111-1111-1111-111111111111", "trink", "192.168.1.1", nil},
        {"11111111-1111-1111-1111-111111111112", "trink", "192.168.1.2", nil}
    },
    {
        {"11111111-1111-1111-1111-111111111111", "trink", "192.168.1.1", 1000},
        {"11111111-1111-1111-1111-111111111112", "trink", "192.168.1.2", 1000}
    },
    {
        {"11111111-1111-1111-1111-111111111111", "trink", "192.168.1.1", 1000},
        {"11111111-1111-1111-1111-111111111112", "trink", "192.168.1.2", 1000}
    }
}

geo = require "geoip.heka"

local msg = {
    Timestamp = nil,
    Logger = nil,
    Hostname = "bastion.host",
    Fields = {
        programname         = "sshd",
        authmsg             = "Accepted",
        user                = "",
        ssh_remote_ipaddr   = ""
    }
}

function process_message()
    for i,v in ipairs(tests) do
        msg.Logger = string.format("generate_sshd_%d", i)
        for _,v2 in ipairs(v) do
            msg.Uuid = v2[1]
            msg.Fields.user = v2[2]
            msg.Fields.ssh_remote_ipaddr = v2[3]
            -- Since we are reusing the same message, strip any city/country fields
            -- that could have been added from the previous loop
            msg.Fields.ssh_remote_ipaddr_city = nil
            msg.Fields.ssh_remote_ipaddr_country = nil
            geo.add_geoip(msg, "ssh_remote_ipaddr")
            if v2[4] then
                msg.Timestamp = (os.time() - v2[4]) * 1e9
            else
                msg.Timestamp = nil
            end
            inject_message(msg)
        end
    end

    return 0
end

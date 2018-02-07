-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Generates test data for moz_security_sshd_login_monitor
--]]


local tests = {
    {"11111111-1111-1111-1111-111111111111", "trink", "192.168.1.1"},
    {"11111111-1111-1111-1111-111111111112", "trink", "192.168.1.2"}
}

geo = require "geoip.heka"

local msg = {
    Timestamp = nil,
    Logger = read_config("logger"),
    Fields = {
        programname         = "sshd",
        authmsg             = "Accepted",
        user                = "",
        ssh_remote_ipaddr   = ""
    }
}

function process_message()
    for i,v in ipairs(tests) do
        msg.Uuid = v[1]
        msg.Fields.user = v[2]
        msg.Fields.ssh_remote_ipaddr = v[3]
        geo.add_geoip(msg, "ssh_remote_ipaddr")
        inject_message(msg)
    end
    return 0
end

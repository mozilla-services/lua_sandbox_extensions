-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Generates test data for moz_security_sshd_login_monitor
--]]

require "date"

local fmt = "%Y-%m-%d %H:%M:%S"
local tests = {
    {"2017-07-24 09:20:01", "trink" , "192.168.1.1"}, -- ok
    {"2017-07-22 02:33:44", "sat"   , "192.168.1.2"}, -- Saturday
    {"2017-07-23 01:11:12", "sun"   , "192.168.1.3"}, -- Sunday
    {"2017-07-23 17:00:00", "abh"   , "192.168.1.4"}, -- after business hours
    {"2017-07-23 08:59:59", "bbh"   , "192.168.1.5"}, -- before business hours
    {"2017-09-04 10:11:12", "trink" , "192.168.1.6"}, -- Labor Day with user_map
    {"2017-05-28 10:11:12", "root"  , "192.168.1.7"}, -- Memorial Day
}

local msg = {
    Timestamp = nil,
    Logger = "input.syslog",
    Fields = {
        programname     = "sshd",
        sshd_authmsg    = "Accepted",
        remote_user     = "",
        remote_addr     = ""
    }
}

function process_message()
    for i,v in ipairs(tests) do
        msg.Timestamp = date.time(v[1], fmt, "America/Los_Angeles")
        msg.Fields.remote_user = v[2]
        msg.Fields.remote_addr = v[3]
        inject_message(msg)
    end
    return 0
end

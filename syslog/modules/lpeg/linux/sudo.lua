-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

-- Copyright 2015 Mathieu Parent <math.parent@gmail.com>

--[[
# Linux sudo Grammar Module

## Variables
### LPEG Grammars
* `syslog_grammar`
--]]

local l = require "lpeg"
l.locale(l)
local string = require "string"
local sl = require "lpeg.syslog"
local pam = require "lpeg.linux.pam".syslog_grammar

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local function sudo_field(name)
    return (l.P(name) * l.P"=" * sl.capture_followed_by("sudo_" .. string.lower(name), " ; "))^-1
end

syslog_grammar = l.Ct(
    sl.capture_followed_by("sudo_message", l.P" : ")
    * sudo_field("TTY")
    * sudo_field("PWD")
    * sudo_field("USER")
    * sudo_field("GROUP")
    * sudo_field("TSID")
    * sudo_field("ENV")
    * l.P"COMMAND=" * l.Cg(l.P(1)^1, "sudo_command")
    )
    + pam

return M

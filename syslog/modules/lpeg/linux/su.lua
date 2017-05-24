-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

-- Copyright 2015 Mathieu Parent <math.parent@gmail.com>

--[[
# Linux su Grammar Module

## Variables
### LPEG Grammars
* `syslog_grammar`
--]]

local l = require "lpeg"
l.locale(l)
local sl = require "lpeg.syslog"
local pam = require "lpeg.linux.pam".syslog_grammar

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

syslog_grammar = l.Ct(
    (
        l.Cg(l.P"Successful" + l.P"FAILED", "su_status")
        * l.P" su for "
        * sl.capture_followed_by("su_name", " by ")
        * l.Cg(l.P(1)^1, "su_oldname")
        )
    + (
        l.P"pam_authenticate: "
        * l.Cg(l.P(1)^1, "pam_error")
        )
    + (
        l.S"+-" * l.space
        * sl.capture_followed_by("pty", " ") -- pseudo terminal
        * sl.capture_followed_by("su_oldname", ":")
        * l.Cg(l.P(1)^1, "su_name")
        )
    ) 
    + pam

return M

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

-- Copyright 2015 Mathieu Parent <math.parent@gmail.com>

--[[
# Linux systemd-logind Grammar Module

## Variables
### LPEG Grammars
* `syslog_grammar`
--]]

local l = require "lpeg"
l.locale(l)
local sl = require "lpeg.syslog"

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

syslog_grammar = l.Ct(
    (
        l.P"New session "
        * l.Cg(l.P"c" , "session_type")^-1 * l.Cg(sl.integer, "session_id")
        * l.P" of user "
        * sl.capture_followed_by("user_id", "." * l.P(-1))
        * l.Cg(l.Cc("SESSION_START"), "sd_message")
    )
    + (
        l.P"Removed session "
        * l.Cg(sl.integer, "session_id")
        * l.P"."
        * l.Cg(l.Cc("SESSION_STOP"), "sd_message")
        * l.P(-1)
        )
    )

return M

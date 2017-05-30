-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

-- Copyright 2015 Mathieu Parent <math.parent@gmail.com>

--[[
# Linux login Grammar Module

## Variables
### LPEG Grammars
* `syslog_grammar`
--]]

local l = require "lpeg"
l.locale(l)
local sl = require "lpeg.syslog"

local tonumber = tonumber

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

syslog_grammar = l.Ct(
    (
        l.P"FAILED LOGIN ("
        * l.Cg(l.digit^1 / tonumber, "failcount")
        * l.P")"
        * l.P" on '"
        * sl.capture_followed_by("tty", "'")
        * (l.P" from '" * sl.capture_followed_by("from", "'"))^-1
        * l.P" FOR '"
        * sl.capture_followed_by("user", "', ")
        * l.Cg(l.P(1)^1, "pam_error")
        )
    + (
        l.P"ROOT LOGIN "
        * l.P" on '"
        * sl.capture_followed_by("tty", "'")
        * (l.P" from '" * sl.capture_followed_by("from", "'"))^-1
        * l.P(-1)
        )
    )

return M

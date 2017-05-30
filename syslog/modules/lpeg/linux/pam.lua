-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

-- Copyright 2015 Mathieu Parent <math.parent@gmail.com>

--[[
# Linux PAM Grammar Module

The primary use case for this grammar is its inclusion into other programname
grammars such as su, sudo, CRON etc.

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

local pam_header = l.Cg(l.P"pam_" * (l.P(1) - "(")^1, "pam_module") * l.P"("
                 * sl.capture_followed_by("pam_service", ":")
                 * sl.capture_followed_by("pam_type", "): ")

syslog_grammar = l.Ct(
    (
        pam_header
        * l.Cg(l.P"session opened", "pam_action")
        * l.P" for user "
        * sl.capture_followed_by("user_name", " by ")
        * sl.capture_followed_by("login_name", "(uid=")
        * l.Cg(l.digit^1 / tonumber, "uid")
        * l.P")"
        )
    + (
        pam_header
        * l.Cg(l.P"session closed", "pam_action")
        * l.P" for user "
        * l.Cg(l.P(1)^1, "user_name")
        )
    + (
        pam_header
        * l.Cg(l.P"authentication failure", "pam_action")
        * l.P"; logname="
        * sl.capture_followed_by("logname", " uid=")
        * l.Cg(l.digit^1 / tonumber, "uid")
        * l.P" euid="
        * l.Cg(l.digit^1 / tonumber, "euid")
        * l.P" tty="
        * sl.capture_followed_by("tty", " ruser=")
        * sl.capture_followed_by("ruser", " rhost=")
        * l.Cg((l.P(1) - l.P("  user="))^0, "rhost")
        * l.P" " -- duplicate space
        * (l.P" user=" * l.Cg(l.P(1)^1, "user"))^-1
        )
    + (
        pam_header
        * l.P"check pass; user "
        * (l.P"(" * sl.capture_followed_by("user_name", ") "))^-1
        * l.P"unknown"
        )
    )

return M

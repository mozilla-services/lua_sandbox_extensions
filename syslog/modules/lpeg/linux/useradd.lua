-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

-- Copyright 2015 Mathieu Parent <math.parent@gmail.com>

--[[
# Linux useradd Grammar Module

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
        l.P"new user: name="
        * sl.capture_followed_by("user_name", ", UID=")
        * l.Cg(l.digit^1 / tonumber, "uid")
        * l.P", GID="
        * l.Cg(l.digit^1 / tonumber, "gid")
        * l.P", home="
        * sl.capture_followed_by("user_home", ", shell=")
        * l.Cg(l.P(1)^1, "user_shell")
        )
    + (
        l.P"add '"
        * sl.capture_followed_by("user_name", l.P"' to group '" + l.P"' to shadow group '")
        * sl.capture_followed_by("group_name", "'")
        * l.P(-1)
        )
    )

return M

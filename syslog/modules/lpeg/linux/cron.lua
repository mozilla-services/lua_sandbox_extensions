-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

-- Copyright 2015 Mathieu Parent <math.parent@gmail.com>

--[[
# Linux CRON Grammar Module

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
    l.P"("
    * sl.capture_followed_by("cron_username", ") ")
    * sl.capture_followed_by("cron_event", " (")
    * sl.capture_followed_by("cron_detail", ")")
    * l.P(-1)
    )
    + pam

return M

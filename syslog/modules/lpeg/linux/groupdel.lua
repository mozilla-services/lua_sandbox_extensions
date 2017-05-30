-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

-- Copyright 2015 Mathieu Parent <math.parent@gmail.com>

--[[
# Linux groupdel Grammar Module

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
        l.P"group '"
        * sl.capture_followed_by("group_name", "' removed")
        * (l.P" from " * l.Cg(l.P(1)^1, "group_dbname"))^-1
        )
    )

return M

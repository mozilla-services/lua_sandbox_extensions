-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# syslog_doc demo module with match args

## Variables
### LPEG Grammars
* `demo` - replaces hostname match with the provided CArg
--]]

-- Imports
local l = require "lpeg"
l.locale(l)

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module
demo = l.Ct(l.Cg(l.Carg(1), "real_hostname"))
return M

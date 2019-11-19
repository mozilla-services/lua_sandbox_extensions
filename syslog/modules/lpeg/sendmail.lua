-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Sendmail module

## Variables
### LPEG Grammars
* `grammar`
--]]

local l = require "lpeg"
l.locale(l) -- we want l.alpha etc...

local rawset = rawset

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local sep = l.P", "
local key = l.C(l.alpha^1)
local value = l.C((l.P(1) - sep)^1)
local statpair = l.Cg(l.C(l.P"stat") * "=" * l.C(l.P(1)^0))
local normalpair = l.Cg(key * "=" * value) * sep^-1
local pair = statpair + normalpair

local sendmailid = l.Cg(l.alnum^-8 * l.digit^6, "sendmailid") * l.P": "

grammar = l.Cf(l.Ct(sendmailid) * pair^0, rawset)

return M

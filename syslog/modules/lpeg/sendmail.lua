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

local space = l.space^0
local key = l.C(l.alpha^1) * space
local value = l.C((l.P(1) - l.P', ')^1) * space
-- l.R(" +","-~")^1) * space
local sep = l.P',' * space
local pair = l.Cg(key * "=" * value) * sep^-1

local sendmailid = l.Cg(l.alnum^1, 'sendmailid') * l.P': '

grammar = l.Cf(l.Ct(sendmailid) * pair^0, rawset)

return M

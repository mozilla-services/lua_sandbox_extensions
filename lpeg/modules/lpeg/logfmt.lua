-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# logfmt Parser Module

See: https://godoc.org/github.com/kr/logfmt

## Variables
### LPEG Grammars
* `grammar` - logfmt grammar
--]]

-- Imports
local l     = require "lpeg"
l.locale(l)
local es    = require "lpeg.escape_sequences"

local rawset = rawset

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local ident_byte    = 1 - (l.R"\0\32" + l.S'="')
local string_byte   = 1 - l.S'"\\'
local garbage       = 1 - ident_byte
local ident         = ident_byte^1
local key           = l.C(ident)
local value         = l.C(ident) + ('"' * l.Cs((string_byte + es.json)^0) * '"')
local pair          = garbage^0 * l.Cg((key * "=" * value) + (key * "=" * l.C"") + (key * l.Cc(true)))

grammar = l.Cf(l.Ct"" * pair^0, rawset)

return M

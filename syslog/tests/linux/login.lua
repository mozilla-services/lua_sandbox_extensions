-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local grammar = require "lpeg.linux.login".syslog_grammar
local log
local fields

log = "FAILED LOGIN (1) on '/dev/tty1' FOR 'root', Authentication failure"
fields = grammar:match(log)
assert(fields.failcount == 1, fields.failcount)
assert(fields.tty == '/dev/tty1', fields.tty)
assert(fields.user == 'root', fields.user)
assert(fields.pam_error == 'Authentication failure', fields.pam_error)

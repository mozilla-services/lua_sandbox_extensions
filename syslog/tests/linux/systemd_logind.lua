-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local grammar = require "lpeg.linux.systemd_logind".syslog_grammar
local log
local fields

log = "New session 42 of user sathieu."
fields = grammar:match(log)
assert(fields.sd_message == 'SESSION_START', fields.sd_message)
assert(fields.session_id == 42, fields.session_id)
assert(fields.user_id == 'sathieu', fields.user_id)

log = "Removed session 42."
fields = grammar:match(log)
assert(fields.sd_message == 'SESSION_STOP', fields.sd_message)
assert(fields.session_id == 42, fields.session_id)

log = "New session c43046 of user root."
fields = grammar:match(log)
assert(fields.sd_message == 'SESSION_START', fields.sd_message)
assert(fields.session_id == 43046, fields.session_id)
assert(fields.session_type == "c", fields.session_type)

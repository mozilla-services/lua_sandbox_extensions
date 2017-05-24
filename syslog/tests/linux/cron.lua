-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local grammar = require "lpeg.linux.cron".syslog_grammar
local log
local fields

log = '(root) CMD ( cd / && run-parts --report /etc/cron.hourly)'
fields = grammar:match(log)
assert(fields.cron_username == 'root', fields.cron_username)
assert(fields.cron_event == 'CMD', fields.cron_event)
assert(fields.cron_detail == ' cd / && run-parts --report /etc/cron.hourly', fields.cron_detail)

log = '(root) LIST (root)'
fields = grammar:match(log)
assert(fields.cron_username == 'root', fields.cron_username)
assert(fields.cron_event == 'LIST', fields.cron_event)
assert(fields.cron_detail == 'root', fields.cron_detail)

log = "pam_unix(cron:session): session opened for user smith by (uid=0)"
fields = grammar:match(log)
assert(fields.pam_module == 'pam_unix', fields.pam_module)
assert(fields.pam_service == 'cron', fields.pam_service)
assert(fields.pam_type == 'session', fields.pam_type)
assert(fields.pam_action == 'session opened', fields.pam_action)
assert(fields.user_name == 'smith', fields.user_name)
assert(fields.uid == 0, fields.uid)

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local grammar = require "lpeg.linux.su".syslog_grammar
local log
local fields

log = "Successful su for root by smith"
fields = grammar:match(log)
assert(fields.su_status == "Successful", fields.su_status)
assert(fields.su_name == "root", fields.su_name)
assert(fields.su_oldname == "smith", fields.su_oldname)

log = "FAILED su for root by smith"
fields = grammar:match(log)
assert(fields.su_status == "FAILED", fields.su_status)
assert(fields.su_name == "root", fields.su_name)
assert(fields.su_oldname == "smith", fields.su_oldname)

log = "pam_authenticate: Authentication failure"
fields = grammar:match(log)
assert(fields.pam_error == "Authentication failure", fields.pam_error)

log = "+ /dev/pts/17 smith:root"
fields = grammar:match(log)
assert(fields.pty == "/dev/pts/17", fields.pty)
assert(fields.su_name == "root", fields.su_name)
assert(fields.su_oldname == "smith", fields.su_oldname)

log = "- /dev/pts/17 smith:root"
fields = grammar:match(log)
assert(fields.pty == "/dev/pts/17", fields.pty)
assert(fields.su_name == "root", fields.su_name)
assert(fields.su_oldname == "smith", fields.su_oldname)

log = "pam_unix(su:auth): session opened for user smith by (uid=0)"
fields = grammar:match(log)
assert(fields.pam_module == 'pam_unix', fields.pam_module)
assert(fields.pam_service == 'su', fields.pam_service)
assert(fields.pam_type == 'auth', fields.pam_type)
assert(fields.pam_action == 'session opened', fields.pam_action)
assert(fields.user_name == 'smith', fields.user_name)
assert(fields.uid == 0, fields.uid)

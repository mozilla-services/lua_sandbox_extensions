-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local grammar = require "lpeg.linux.pam".syslog_grammar
local log
local fields

log = "pam_unix(login:session): session opened for user sathieu by LOGIN(uid=1000)"
fields = grammar:match(log)
assert(fields.pam_module == 'pam_unix', fields.pam_module)
assert(fields.pam_service == 'login', fields.pam_service)
assert(fields.pam_type == 'session', fields.pam_type)
assert(fields.pam_action == 'session opened', fields.pam_action)
assert(fields.user_name == 'sathieu', fields.user_name)
assert(fields.uid == 1000, fields.uid)

log = "pam_unix(login:auth): authentication failure; logname=LOGIN uid=0 euid=0 tty=/dev/tty1 ruser= rhost=  user=root"
fields = grammar:match(log)
assert(fields.pam_module == 'pam_unix', fields.pam_module)
assert(fields.pam_service == 'login', fields.pam_service)
assert(fields.pam_type == 'auth', fields.pam_type)
assert(fields.pam_action == 'authentication failure', fields.pam_action)
assert(fields.logname == 'LOGIN', fields.logname)
assert(fields.uid == 0, fields.uid)
assert(fields.euid == 0, fields.euid)
assert(fields.tty == '/dev/tty1', fields.tty)
assert(fields.ruser == '', fields.ruser)
assert(fields.rhost == '', fields.rhost)
assert(fields.user == 'root', fields.user)

log = "pam_unix(login:session): session closed for user sathieu"
fields = grammar:match(log)
assert(fields.pam_module == 'pam_unix', fields.pam_module)
assert(fields.pam_service == 'login', fields.pam_service)
assert(fields.pam_type == 'session', fields.pam_type)
assert(fields.pam_action == 'session closed', fields.pam_action)
assert(fields.user_name == 'sathieu', fields.user_name)

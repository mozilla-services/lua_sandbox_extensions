-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local grammar = require "lpeg.linux.sudo".syslog_grammar
local log
local fields

log = "usrnagios : TTY=unknown ; PWD=/home/usrnagios ; USER=root ; COMMAND=/usr/bin/ctdb -Y status"
fields = grammar:match(log)
assert(fields.sudo_message == 'usrnagios', fields.sudo_message)
assert(fields.sudo_tty == 'unknown', fields.sudo_tty)
assert(fields.sudo_pwd == '/home/usrnagios', fields.sudo_pwd)
assert(fields.sudo_user == 'root', fields.sudo_user)
assert(fields.sudo_command == '/usr/bin/ctdb -Y status', fields.sudo_command)

log = "pam_unix(sudo:session): session opened for user smith by (uid=0)"
fields = grammar:match(log)
assert(fields.pam_module == 'pam_unix', fields.pam_module)
assert(fields.pam_service == 'sudo', fields.pam_service)
assert(fields.pam_type == 'session', fields.pam_type)
assert(fields.pam_action == 'session opened', fields.pam_action)
assert(fields.user_name == 'smith', fields.user_name)
assert(fields.uid == 0, fields.uid)

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local grammar = require "lpeg.linux.sshd".syslog_grammar
local log
local fields

log = 'Accepted publickey for sathieu from 10.11.12.13 port 4242 ssh2'
fields = grammar:match(log)
assert(fields.sshd_authmsg == 'Accepted', fields.sshd_authmsg)
assert(fields.sshd_method == 'publickey', fields.sshd_method)
assert(fields.remote_user == 'sathieu', fields.remote_user)
assert(fields.remote_addr.value == '10.11.12.13', fields.remote_addr)
assert(fields.remote_port == 4242, fields.remote_port)

log = "Failed password for invalid user administrator from 10.20.30.40 port 4242 ssh2"
fields = grammar:match(log)
assert(fields.sshd_authmsg == 'Failed', fields.sshd_authmsg)
assert(fields.sshd_method == 'password', fields.sshd_method)
assert(fields.remote_user == 'administrator', fields.remote_user)
assert(fields.remote_addr.value == '10.20.30.40', fields.remote_addr)
assert(fields.remote_port == 4242, fields.remote_port)

log = "Received disconnect from 10.2.3.4: 11: The user disconnected the application [preauth]"
fields = grammar:match(log)
assert(fields.remote_addr.value == '10.2.3.4', fields.remote_addr)
assert(fields.disconnect_reason == 11, fields.disconnect_reason)
assert(fields.disconnect_msg == 'The user disconnected the application [preauth]', fields.disconnect_msg)

log = "Connection from 121.18.238.123 port 60512 on 172.31.41.219 port 22"
fields = grammar:match(log)
assert(fields.remote_addr.value == '121.18.238.123', fields.remote_addr)
assert(fields.remote_port == 60512, fields.remote_port)
assert(fields.local_addr.value == '172.31.41.219', fields.local_addr)
assert(fields.local_port == 22, fields.local_port)

log = "Set /proc/self/oom_score_adj to 0"
fields = grammar:match(log)
assert(fields.set == log, fields.set)

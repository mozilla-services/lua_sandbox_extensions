-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local grammar = require "lpeg.linux.useradd".syslog_grammar
local log
local fields

log = "new user: name=smith, UID=1233, GID=1234, home=/home/smith, shell=/bin/bash"
fields = grammar:match(log)
assert(fields.user_name == "smith", fields.user_name)
assert(fields.uid == 1233, tostring(fields.uid))
assert(fields.gid == 1234, tostring(fields.gid))
assert(fields.user_home == "/home/smith", fields.user_home)
assert(fields.user_shell == "/bin/bash",  fields.user_shell)

log = "add 'smith' to group 'gsmith'"
fields = grammar:match(log)
assert(fields.user_name == "smith", fields.user_name)
assert(fields.group_name == "gsmith",  fields.group_name)

log = "add 'smith' to shadow group 'sgsmith'"
fields = grammar:match(log)
assert(fields.user_name == "smith", fields.user_name)
assert(fields.group_name == "sgsmith",  fields.group_name)

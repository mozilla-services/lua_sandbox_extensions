-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local grammar = require "lpeg.linux.groupdel".syslog_grammar
local log
local fields

log = "group 'admin' removed from dbname"
fields = grammar:match(log)
assert(fields.group_name == "admin", fields.group_name)
assert(fields.group_dbname == "dbname", fields.group_dbname)

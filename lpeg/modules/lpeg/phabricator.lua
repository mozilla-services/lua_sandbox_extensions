-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Grammars for processing Phabricator log entries

## Variables
### LPEG Grammars
* `access` - matches Phabricator access log entries
--]]

local l     = require "lpeg"
local pfg   = require "lpeg.printf"
local d     = require "lpeg.date_time"
local ip    = require "lpeg.ip_address"

local M = {}
setfenv(1, M)

local tfmt = "[%a, %d %b %Y %H:%M:%S %z]"

local fmt = {
    "%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%d\t%d",
    l.Cg(d.build_strftime_grammar(tfmt) / d.time_to_ns, "timestamp"),
    "pid",
    "hostname",
    l.Cg(ip.v4 + ip.v6, "ip"),
    "user",
    "controller",
    "function",
    "path",
    "referrer",
    "status",
    "rtime"
}

access = pfg.build_grammar(fmt)

return M

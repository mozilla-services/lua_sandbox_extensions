-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"

local libi = require "libinjection"

local sqli = "1 UNION SELECT * FROM TABLE"

state = libi.sqli_state()
assert(state, "sqli_state returned nil")
libi.sqli_init(state, sqli, string.len(sqli), 0)
local v = libi.is_sqli(state)
assert(v == 1, "is_sqli did not return 1")
assert(state.fingerprint == "1UEok", string.format("incorrect fingerprint: %s", state.fingerprint))

local x1 = "');}</style><script>alert(1);</script>"
v = libi.xss(x1, string.len(x1))
assert(v == 1, "xss did not return 1")

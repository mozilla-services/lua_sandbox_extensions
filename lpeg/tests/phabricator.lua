
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "lpeg"
require "string"

local p = require "lpeg.phabricator"

local asample = "[Wed, 08 Aug 2018 17:37:58 +0000]	106002	web.host	127.0.0.1	username	PhabricatorConduitAPIController	bugzilla.account.search	/api/bugzilla.account.search	-	200	57789"
local asamplets = 1533749878 * 1e9

function access()
    local v = p.access:match(asample)
    if not v then error(asample) end
    assert(v.timestamp == asamplets, string.format("%d", v.timestamp))
    assert(v.ip == "127.0.0.1", v.ip)
end

access()

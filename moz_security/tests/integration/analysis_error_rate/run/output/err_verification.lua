-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Validate output of moz_security_http_error_rate
--]]

require "string"

local result = [[error_threshold	50
cms_size	3
10.0.2.10	75
10.0.2.12	500
]]

local cnt = 0

function process_message()
    local payload = read_message("Payload")
    assert(result == payload, payload)
    cnt = 1
    return 0
end

function timer_event()
    assert(cnt == 1, string.format("%d out of 1 tests ran", cnt))
end

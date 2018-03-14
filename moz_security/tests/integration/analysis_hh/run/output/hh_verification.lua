-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Validate output of sampled heavy hitter analysis
--]]

require "string"

local result = [[threshold	332.70378875
list_size	1742
event_count	193190
192.168.0.1	1500
192.168.0.10	1500
192.168.0.11	1500
192.168.0.12	1500
192.168.0.13	1500
192.168.0.14	1500
192.168.0.15	1500
192.168.0.16	1500
192.168.0.17	1500
192.168.0.18	1500
192.168.0.19	1500
192.168.0.2	1500
192.168.0.20	1500
192.168.0.3	1500
192.168.0.4	1500
192.168.0.5	1500
192.168.0.6	1500
192.168.0.7	1500
192.168.0.8	1500
192.168.0.9	1500
192.168.1.1	1000
192.168.1.10	1000
192.168.1.2	1000
192.168.1.3	1000
192.168.1.4	1000
192.168.1.5	1000
192.168.1.6	1000
192.168.1.7	1000
192.168.1.8	1000
192.168.1.9	1000
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

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Validates the moz_telemetry_heavy_hitters_monitor output
--]]

require "string"

local result =[[60	1051
40	1031
10	1001
30	1021
70	1061
100	1091
50	1041
80	1071
90	1081
20	1011
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

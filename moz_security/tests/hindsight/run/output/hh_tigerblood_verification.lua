-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Validates the moz_security_heavy_hitters output for Tigerblood
--]]

require "string"

local result = '[{"violation":"fxa:heavy_hitter_ip","weight":60,"ip":"1051"}' ..
    ',{"violation":"fxa:heavy_hitter_ip","weight":40,"ip":"1031"}' ..
    ',{"violation":"fxa:heavy_hitter_ip","weight":10,"ip":"1001"}' ..
    ',{"violation":"fxa:heavy_hitter_ip","weight":30,"ip":"1021"}' ..
    ',{"violation":"fxa:heavy_hitter_ip","weight":70,"ip":"1061"}' ..
    ',{"violation":"fxa:heavy_hitter_ip","weight":100,"ip":"1091"}' ..
    ',{"violation":"fxa:heavy_hitter_ip","weight":50,"ip":"1041"},' ..
    '{"violation":"fxa:heavy_hitter_ip","weight":80,"ip":"1071"},' ..
    '{"violation":"fxa:heavy_hitter_ip","weight":90,"ip":"1081"},' ..
    '{"violation":"fxa:heavy_hitter_ip","weight":20,"ip":"1011"}]'

local cnt = 0
function process_message()
    local violations = read_message("Fields[violations]")
    assert(result == violations, violations)
    cnt = 1
    return 0
end


function timer_event()
    assert(cnt == 1, string.format("%d out of 1 tests ran", cnt))
end

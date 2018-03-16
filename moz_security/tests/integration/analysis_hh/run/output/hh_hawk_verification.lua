-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Validate output of sampled heavy hitter analysis, Tigerblood output
--]]

require "string"

local violations = "[{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.0.1\"}" ..
    ",{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.0.10\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.0.11\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.0.12\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.0.13\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.0.14\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.0.15\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.0.16\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.0.17\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.0.18\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.0.19\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.0.2\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.0.20\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.0.3\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.0.4\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.0.5\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.0.6\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.0.7\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.0.8\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.0.9\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.1.1\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.1.10\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.1.2\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.1.3\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.1.4\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.1.5\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.1.6\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.1.7\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.1.8\"}," ..
    "{\"violation\":\"fxa:heavy_hitter_ip\",\"ip\":\"192.168.1.9\"}]"

local cnt = 0

function process_message()
    local v = read_message("Fields[violations]") or error("message missing violations field")
    if v ~= violations then
        error("message violation value did not match")
    end
    cnt = 1
    return 0
end


function timer_event()
    assert(cnt == 1, string.format("%d out of 1 tests ran", cnt))
end

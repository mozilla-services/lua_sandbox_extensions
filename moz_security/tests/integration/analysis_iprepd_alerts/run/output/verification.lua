-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"

-- results table corresponds to input test table and analysis configuration
local results = {
    "[hhfxa] iprepd adjust 192.168.0.251 to 75 (set key 192.168.0.251|75) on violation fxa:heavy_hitter_ip",
    "[hhfxa] iprepd adjust 192.168.0.251 to 25 (set key 192.168.0.251|25) on violation fxa:heavy_hitter_ip",
    "[hhfxa] iprepd adjust 192.168.1.1 to 40 (set key 192.168.1.1|50) on violation fxa:heavy_hitter_ip"
}

local cnt = 1

function process_message()
    local summary   = read_message("Fields[summary]") or error("no summary field")
    local irc_targ  = read_message("Fields[irc.target]") or error("no target field")

    if summary ~= results[cnt] then
        error(string.format("test cnt:%d %s", cnt, summary))
    end
    cnt = cnt + 1
    return 0
end


function timer_event()
    assert(cnt-1 == #results, string.format("test %d out of %d tests ran", cnt-1, #results))
end

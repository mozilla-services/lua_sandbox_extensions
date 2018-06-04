-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Generates sample authentication events for auth_lastx

--]]

require "os"
require "string"

local sdec = require "decoders.moz_logging.json_heka"

-- test table, array indices correspond to analysis and output configurations
local test = {
    '{"Timestamp":1527793163391080451,"Time":"2018-05-31T18:59:23Z","Type":"app.log"' ..
        ',"Logger":"iprepd","Hostname":"testhost","EnvVersion":"2.0","Pid":34198,"Severity":6' ..
        ',"Fields":{"exception":false,"ip":"192.168.0.251","msg":"violation applied",' ..
        '"original_reputation":100,"reputation":80,"violation":"fxa:heavy_hitter_ip"}}',
    '{"Timestamp":1527793163391080451,"Time":"2018-05-31T18:59:23Z","Type":"app.log"' ..
        ',"Logger":"iprepd","Hostname":"testhost","EnvVersion":"2.0","Pid":34198,"Severity":6' ..
        ',"Fields":{"exception":false,"ip":"192.168.0.251","msg":"violation applied",' ..
        '"original_reputation":80,"reputation":75,"violation":"fxa:heavy_hitter_ip"}}',

    -- next two should be throttled by alerting module
    '{"Timestamp":1527793163391080451,"Time":"2018-05-31T18:59:23Z","Type":"app.log"' ..
        ',"Logger":"iprepd","Hostname":"testhost","EnvVersion":"2.0","Pid":34198,"Severity":6' ..
        ',"Fields":{"exception":false,"ip":"192.168.0.251","msg":"violation applied",' ..
        '"original_reputation":80,"reputation":75,"violation":"fxa:heavy_hitter_ip"}}',
    '{"Timestamp":1527793163391080451,"Time":"2018-05-31T18:59:23Z","Type":"app.log"' ..
        ',"Logger":"iprepd","Hostname":"testhost","EnvVersion":"2.0","Pid":34198,"Severity":6' ..
        ',"Fields":{"exception":false,"ip":"192.168.0.251","msg":"violation applied",' ..
        '"original_reputation":80,"reputation":75,"violation":"fxa:heavy_hitter_ip"}}',

    '{"Timestamp":1527793163391080451,"Time":"2018-05-31T18:59:23Z","Type":"app.log"' ..
        ',"Logger":"iprepd","Hostname":"testhost","EnvVersion":"2.0","Pid":34198,"Severity":6' ..
        ',"Fields":{"exception":false,"ip":"192.168.0.251","msg":"violation applied",' ..
        '"original_reputation":75,"reputation":25,"violation":"fxa:heavy_hitter_ip"}}',

    -- send one with an exception which should not result in an alert
    '{"Timestamp":1527793163391080451,"Time":"2018-05-31T18:59:23Z","Type":"app.log"' ..
        ',"Logger":"iprepd","Hostname":"testhost","EnvVersion":"2.0","Pid":34198,"Severity":6' ..
        ',"Fields":{"exception":true,"ip":"192.168.1.1","msg":"violation applied",' ..
        '"original_reputation":75,"reputation":25,"violation":"fxa:heavy_hitter_ip"}}',

    '{"Timestamp":1527793163391080451,"Time":"2018-05-31T18:59:23Z","Type":"app.log"' ..
        ',"Logger":"iprepd","Hostname":"testhost","EnvVersion":"2.0","Pid":34198,"Severity":6' ..
        ',"Fields":{"exception":false,"ip":"192.168.1.1","msg":"violation applied",' ..
        '"original_reputation":75,"reputation":40,"violation":"fxa:heavy_hitter_ip"}}'
}

-- default message headers
local msg = {
    Timestamp = nil,
    Logger = "generate_data",
    Hostname = "bastion.host"
}

function process_message()
    for i,v in ipairs(test) do
        sdec.decode(v, msg, false)
    end
    return 0
end

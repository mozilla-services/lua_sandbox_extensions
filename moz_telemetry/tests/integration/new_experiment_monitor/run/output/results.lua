-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Validates the moz_telemetry_new_experiment_monitor alerts
--]]

require "string"

local cnt = 1
function process_message()
    local payload = read_message("Payload")
    -- We expect two messages. Let's make sure we got them.
    if cnt == 1 then
        assert(payload:match("foo"), payload)
    elseif cnt == 2 then
        assert(payload:match("bar"), payload)
    end
    cnt = cnt + 1
    return 0
end


function timer_event()
    assert(cnt == 2, string.format("%d out of 2 expected alerts were received", cnt))
end

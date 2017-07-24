-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Validates the moz_telemetry_doctype_monitor alerts
--]]

require "string"

local results = {
    "user: sat\nip: 192.168.1.2\n",
    "user: sun\nip: 192.168.1.3\n",
    "user: abh\nip: 192.168.1.4\n",
    "user: bbh\nip: 192.168.1.5\n",
    "user: mtrinkala\nip: 192.168.1.6\n",
    "user: root\nip: 192.168.1.7\n",
}

local cnt = 0
function process_message()
    local payload = read_message("Payload")
    if results[cnt + 1] ~= payload then
        error(string.format("test:%d result:%s", cnt + 1, payload))
    end
    cnt = cnt + 1
    return 0
end


function timer_event()
    assert(cnt == 6, string.format("%d out of 6 tests ran", cnt))
end

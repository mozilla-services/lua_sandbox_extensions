-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Validates the moz_telemetry_mobile_monitor alerts
--]]

require "string"

local results = {
    "foo_bar_core - No new valid data has been seen in 10 minutes\n",
    [[Ingestion Data for the Last Hour
================================
valid            : 1049
error            : 12
percent_error    : 1.13101
max_percent_error: 1

Diagnostic (count/error)
========================
5	error type 1
4	error type 2
3	error type 3
]],
}

local cnt = 0
function process_message()
    local id = read_message("Fields[id]")
    local payload = read_message("Payload")
    cnt = cnt + 1
    assert(results[cnt] == payload, payload)
    return 0
end


function timer_event()
    assert(cnt == #results, string.format("%d out of %d tests ran", cnt, #results))
end

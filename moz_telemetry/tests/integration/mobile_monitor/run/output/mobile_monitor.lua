-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Validates the moz_telemetry_mobile_monitor alerts
--]]

require "string"

local results = {
    [[Focus_iOS_core - No new valid data has been seen in 5 minutes

Stats for the last 61 minutes
=============================
Submissions       : 55
Minutes with data : 55
Quantile data gap : 0
]],
    [[Ingestion Data for the Last Hour
================================
valid            : 1053
error            : 12
percent_error    : 1.12676
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
    if results[cnt] ~= payload then
        error(string.format("test: %d %s", cnt, payload))
    end
    return 0
end


function timer_event()
    assert(cnt == #results, string.format("%d out of %d tests ran", cnt, #results))
end

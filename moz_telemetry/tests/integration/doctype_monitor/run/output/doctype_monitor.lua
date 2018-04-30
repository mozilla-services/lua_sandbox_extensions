-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Validates the moz_telemetry_doctype_monitor alerts
--]]

require "string"

local results = {
    nightly = [[
The average message size has changed by 11.9583% (current avg: 167B)

graph: https://integration_test/dashboard_output/graphs/analysis.doctype_monitor.size.html
]],
    aurora =
[[
Ingestion Data for the Last Hour
================================
valid            : 1140
error            : 48
percent_error    : 4.0404
max_percent_error: 4

graph: https://integration_test/dashboard_output/graphs/analysis.doctype_monitor.ingestion_error.html

Diagnostic (count/error)
========================
48	foobar
]],
    release =
[[
48% of submissions received after 24 hours expected up to 20%

graph: https://integration_test/dashboard_output/graphs/analysis.doctype_monitor.latency.html
]],
    esr =
[[
Duplicate Data for the Last Hour
================================
unique               : 24000
duplicate            : 1074
percent_duplicate    : 4.28332
max_percent_duplicate: 4

graph: https://integration_test/dashboard_output/graphs/analysis.doctype_monitor.duplicate.html
]],
    Other =
[[
SAX Analysis
============
start time : 19700116 000000
end time   : 19700116 235900
current    : ########################
historical : DDDDDDDDDDDDDDDDDDDDDDDD
mindist    : 36.6951
max_mindist: 0

graph: https://integration_test/dashboard_output/graphs/analysis.doctype_monitor.volume.html
]],
    beta =
[[
historical: 28800 current: 36000  delta: 25%

graph: https://integration_test/dashboard_output/graphs/analysis.doctype_monitor.volume.html
]]
}

local cnt = 0
function process_message()
    local id = read_message("Fields[id]")
    local payload = read_message("Payload")
    assert(results[id] == payload, payload)
    cnt = cnt + 1
    return 0
end


function timer_event()
    assert(cnt == 6, string.format("%d out of 6 tests ran", cnt))
end

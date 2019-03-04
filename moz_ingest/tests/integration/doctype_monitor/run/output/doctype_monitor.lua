-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Validates the moz_telemetry_doctype_monitor alerts
--]]

require "io"
require "string"

local results = {
[[
No new valid data has been seen in 5 minutes

Stats for the Last Hour
=======================
Submissions       : 56
Minutes with data : 56
Quantile data gap : 0
]],
[[
Duplicate Data for the Last Hour
================================
unique               : 3000
duplicate            : 31
percent_duplicate    : 1.02276
max_percent_duplicate: 1
]],
[[
Ingestion Data for the Last Hour
================================
valid            : 3000
error            : 31
percent_error    : 1.02276
max_percent_error: 1

Diagnostic (count/error)
========================
31	foobar
]],
[[
Ingestion Data for the Last Hour
================================
valid            : 3100
error            : 65
percent_error    : 2.05371
max_percent_error: 1

Diagnostic (count/error)
========================
33	parse
32	foobar
]],
}

local cnt = 0
function process_message()
    local payload = read_message("Payload")
    cnt = cnt + 1
    assert(results[cnt] == payload, string.format("test:%d %s", cnt, payload))
    return 0
end


function timer_event()
    local ecnt = #results
    assert(cnt == ecnt, string.format("%d out of %d tests ran", cnt, ecnt))
    local fh = assert(io.open("dashboard/analysis.doctype_monitor.captures.json"))

    local ecap = [[{
"Other":{"success":["submission data to capture"],
"errors":["parse error"]}}
]]
    local acap = fh:read("*a")
    assert(ecap == acap, acap)
    fh:close()
end

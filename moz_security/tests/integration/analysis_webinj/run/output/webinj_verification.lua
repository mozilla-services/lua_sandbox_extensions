-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Validate output of libinjection sandbox
--]]

require "string"

local result = "10.0.0.15	69	" ..
    "GET /sitemap.xml?query=%27%22%3Cscript%3Ealert%281%29%3B%3C%2Fscript%3E HTTP/1.1	" ..
    "GET /sitemap.xml?query=query%22%26timeout+%2FT+15%26%22 HTTP/1.1\n"

local cnt = 0

function process_message()
    local payload = read_message("Payload")
    assert(result == payload, payload)
    cnt = 1
    return 0
end

function timer_event()
    assert(cnt == 1, string.format("%d out of 1 tests ran", cnt))
end

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
require "table"

local captures = {""}
local results = {
}

local cnt = 0
function process_message()
    local t = read_message("Type")
    local m = read_message("Payload")
    cnt = cnt + 1

    local e = results[cnt].type
    if t ~= e then error(string.format("test: %d file received: %s expected: %s", cnt, tostring(t), tostring(e))) end

    e = results[cnt].message
    if m ~= e then error(string.format("test: %d file received: %s expected: %s", cnt, tostring(m), tostring(e))) end

    captures[#captures + 1] = string.format("{type = '%s', error_message = '%s'}", t, m)
    return 0
end

function timer_event(ns)
    inject_payload("txt", "captures", table.concat(captures, ",\n"))
    if cnt ~= #results then error(string.format("messages received %d expected: %d", cnt, #results)) end
end

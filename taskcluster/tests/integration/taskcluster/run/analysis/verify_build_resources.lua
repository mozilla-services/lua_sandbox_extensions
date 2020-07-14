-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "cjson"
require "string"
require "table"

local results = {
{taskId = 'B0K4hI4ISHOF56K3FWeN-w', size = 2723906},
}

local cnt = 0
function process_message()
    local p = read_message("Payload")
    local f = cjson.decode(p)
    cnt = cnt + 1


    local r = f.taskId
    local e = results[cnt].taskId
    if r ~= e then error(string.format("test: %d taskId expected: '%s' received: '%s'", cnt, tostring(e), tostring(r))) end

    r = #p
    e = results[cnt].size
    if r ~= e then error(string.format("test: %d size expected: %d received: %d", cnt, e, r)) end

    return 0
end

function timer_event(ns)
    if cnt ~= #results then error(string.format("messages expected: %d received %d", #results, cnt)) end
end

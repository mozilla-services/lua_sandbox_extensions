-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
require "cjson"

local cnt = 0

local expected = {231097}

function process_message()
    cnt = cnt + 1
    local s = read_message("Payload")
    local r = #s
    local e = expected[cnt]
    if r ~= e then error(string.format("bytes received %d expected: %d", r,  e)) end
    return 0
end

function timer_event(ns)
    if #expected ~= cnt then error(string.format("received %d expected: %d", cnt,  #expected)) end
end

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"

local results = {"autoland", "mozilla-release", "mozilla-central", "mozilla-esr68", "try", "autoland", "mozilla-central", "try"}

local cnt = 0
function process_message()
    local p = read_message("Fields[project]")
    cnt = cnt + 1

    local e = results[cnt]
    if p ~= e then error(string.format("test: %d project received: %s expected: %s", cnt, tostring(p), tostring(e))) end

    return 0
end

function timer_event(ns)
    if cnt ~= #results then error(string.format("messages expected: %d received %d", #results, cnt)) end
end

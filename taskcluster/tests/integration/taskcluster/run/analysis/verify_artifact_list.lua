-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
require "cjson"

local ecnt = 15
local cnt = 0

local expected = {"public/logs/live_backing.log", "public/logs/more.log", "public/logs/more1.log"}

function process_message()
    cnt = cnt + 1
    local j = cjson.decode(read_message("Payload"))
    if j.taskId ==  "AuIAPvWhSiyp0eUh5vAdCw" then
        for i,e in pairs(expected) do
            local r = j.artifacts[i].name
            if r ~= e then error(string.format("received '%s' expected: '%s'", r,  e)) end
        end
    end
    return 0
end

function timer_event(ns)
    if ecnt ~= cnt then error(string.format("received %d expected: %d", cnt,  ecnt)) end
end

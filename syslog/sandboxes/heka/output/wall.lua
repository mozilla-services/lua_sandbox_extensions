-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local execute = require "os".execute
local gsub = require "string".gsub

--[[
#  Output using wall

## wall.cfg
```lua
filename        = "wall.lua"

message_matcher = '(Logger == "input.syslog" || Logger == "input.klog") && Severity <= 0'
```
--]]


function process_message()
    local m = gsub(read_message("Payload"), "'", "\"")
    execute("wall '" .. m .. "'")
    return 0
end

function timer_event(ns)
    -- no op
end

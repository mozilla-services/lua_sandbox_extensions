-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Generates test data for moz_security_heavy_hitters_monitor
--]]

require "string"

local msg = {
    Timestamp = 0,
    Logger = "input.hh",
    Fields = {
        id = "",
    }
}

function process_message()
    for i = 1, 1100 do
        msg.Fields.id = string.format("%04d", i)
        inject_message(msg)
    end

    local cnt = 1
    for i = 1, 1100, 10 do
        msg.Fields.id = string.format("%04d", i)
        for j = 1, cnt do
            inject_message(msg)
        end
        cnt = cnt + 1
    end
    return 0
end

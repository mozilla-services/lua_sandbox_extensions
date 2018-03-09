-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Generates test data for plugin_monitor
--]]
require "io"
require "string"
local socket = require "socket"

local inputs = {
    {Timestamp = 0, Type = "plugin_monitor_test_percent", Payload = "0"},
    {Timestamp = 0, Type = "plugin_monitor_test_minimum", Payload = "0"},
    {Timestamp = 0, Type = "plugin_monitor_test_success", Payload = "0"},
}

local fn = string.format("%s/input/plugin_tsv.cfg", read_config("sandbox_load_path"))
local fh = assert(io.open(fn, "w+"))
fh:write([[filename = "plugins_tsv.lua"
ticker_interval = 1
preserve_data = false
]])
fh:close()

function process_message()
    socket.sleep(3)
    for x = 0, 89 do
        inputs[1].Payload = tostring(x)
        inject_message(inputs[1])
        inputs[2].Payload = tostring(x)
        inject_message(inputs[2])
    end
    for x = 1, 10 do
        inputs[1].Payload = tostring(-x)
        inject_message(inputs[1])
        inputs[2].Payload = tostring(-x)
        inject_message(inputs[2])
    end
    for x = 0, 100 do
        inputs[3].Payload = tostring(x)
        inject_message(inputs[3])
    end
    return 0
end

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Read Kernel log

## Sample Configuration #1
```lua
filename            = "klog.lua"
instruction_limit   = 0

-- input_file (string) - Defaults to /proc/kmsg.
```
--]]

local l = require "lpeg"
l.locale(l)
local math = require "math"

local input_file  = read_config("input_file") or "/proc/kmsg"

local function convert_pri(pri)
    pri = tonumber(pri)
    local facility = math.floor(pri/8)
    local severity = pri % 8

    return {facility = facility, severity = severity}
end
local pri = l.R"09"^-3 / convert_pri

local grammar = l.Ct("<" * l.Cg(pri, "pri") * ">" * l.Cg(l.P(1)^1, "message"))

local msg = {
    Timestamp = nil,
    Type      = read_config("type"),
    Hostname  = nil,
    Payload   = nil,
    Pid       = nil,
    Severity  = nil,
    Fields    = {
        syslogfacility = nil
    }
}

function process_message()
    local fh = assert(require "io".open(input_file, "rb"))
    while is_running() do
        local line = fh:read("*l")
        local fields = grammar:match(line)
        if fields then
            msg.Severity = fields.pri.severity
            msg.Fields.syslogfacility = fields.pri.facility
            msg.Payload = fields.message
        else
            msg.Severity = 5 -- LOG_NOTICE
            msg.Fields.syslogfacility = 0 -- LOG_KERN
            msg.Payload = line
        end
        -- Only send LOG_KERN messages
        if msg.Fields.syslogfacility == 0 then
            inject_message(msg)
        end
    end
    return 0
end

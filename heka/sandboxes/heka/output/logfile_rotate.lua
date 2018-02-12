-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "io"
require "string"
require "os"

--[[
#  Logfile output rotated by size

Outputs decoded data stream rotating the log file every time it reaches the
`rotate_size`.

## Sample Configuration
```lua
filename        = "logfile_rotate.lua"
message_matcher = "TRUE"
ticker_interval = 0

--location where the payload is written
output_dir       = "/var/tmp"
rotate_size      = 1024 * 1024 * 1024
rotate_retention = 10

-- Specify a module that will encode/convert the Heka message into its output representation.
encoder_module = "encoders.heka.framed_protobuf" -- default
```
--]]


local output_dir        = read_config("output_dir") or "/var/tmp"
local output_prefix     = read_config("Logger")
local rotate_size       = read_config("rotate_size") or 1e9
local rotate_retention  = read_config("rotate_retention") or 10
local encoder_module    = read_config("encoder_module") or "encoders.heka.framed_protobuf"
local encode = require(encoder_module).encode
if not encode then
    error(encoder_module .. " does not provide an encode function")
end

local fh
local fn = string.format("%s/%s.log", output_dir, output_prefix)


function process_message()
    if not fh then
        fh, err = io.open(fn, "a")
        if err then return -1, err end
    end

    local ok, data = pcall(encode)
    if not ok then return -1, data end
    if not data then return -2 end
    -- if type(data) == "userdata" then data = tostring(data) end -- uncomment to test the non zero copy behaviour
    fh:write(data)

    if fh:seek() >= rotate_size  then
        fh:close()
        fh = nil

        -- rotate files
        for file_num = rotate_retention, 1, -1 do

            local fn_newer = string.format("%s.%d", fn, file_num - 1)
            if file_num == 1 then -- newer file has never been rotated, so has no suffix
                fn_newer = fn
            end
            local fn_older = string.format("%s.%d", fn, file_num)

            -- Rename file if exist
            local fh_newer, err = io.open(fn_newer, "r")
            if fh_newer then
                fh_newer:close()
                local ok, err = os.rename(fn_newer, fn_older)
                if err then return 1, err end -- Something goes wrong, return fatal error
            end

        end

    end
    return 0
end


function timer_event(ns)
    -- no op
end

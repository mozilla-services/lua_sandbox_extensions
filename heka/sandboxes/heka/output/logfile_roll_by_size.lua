-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "io"
require "string"
require "os"
require "lfs"

--[[
#  Logfile output rolled by size

Outputs decoded data stream rolling the log file every time it reaches the
`roll_size`.

## Sample Configuration
```lua
filename        = "logfile_roll_by_size.lua"
message_matcher = "TRUE"
ticker_interval = 0
preserve_data   = true

--location where the payload is written
output_dir      = "/var/tmp"
roll_size       = 1024 * 1024 * 1024
roll_retention  = 10

-- Specify a module that will encode/convert the Heka message into its output representation.
encoder_module = "encoders.heka.framed_protobuf" -- default
```
--]]


local output_dir        = read_config("output_dir") or "/var/tmp"
local output_prefix     = read_config("Logger")
local roll_size         = read_config("roll_size") or 1e9
local roll_retention    = read_config("roll_retention") or -1
local encoder_module    = read_config("encoder_module") or "encoders.heka.framed_protobuf"
local encode = require(encoder_module).encode
if not encode then
    error(encoder_module .. " does not provide an encode function")
end

local fh
local fn_format = string.format("%s/%s.%%d.log", output_dir, output_prefix)
local fn_regex = string.format("^%s.(%%d+).log$", output_prefix)

-- Search last file_num
file_num = 0
for entry in lfs.dir(output_dir) do
    if lfs.attributes(output_dir.."/"..entry)['mode'] == "file" then
        local file_num_tmp = tonumber(string.match(entry, fn_regex))
        if file_num_tmp and file_num_tmp > file_num then file_num = file_num_tmp end
    end
end

function process_message()
    if not fh then
        local fn = string.format(fn_format, file_num)
        fh, err = io.open(fn, "a")
        if err then return -1, err end
    end

    local ok, data = pcall(encode)
    if not ok then return -1, data end
    if not data then return -2 end
    -- if type(data) == "userdata" then data = tostring(data) end -- uncomment to test the non zero copy behaviour
    fh:write(data)

    if fh:seek() >= roll_size  then
        fh:close()
        fh = nil
        file_num = file_num + 1

        -- delete old files
        if roll_retention > 0 then
            local file_num_old = file_num - roll_retention
            while file_num_old >= 0 do
                local fn_old = string.format(fn_format, file_num_old)
                local fh_old, err = io.open(fn_old, "r")
                if err then
                    break
                end
                fh_old:close()
                local ok, err = os.remove(fn_old)
                if err then return -1, err end
                file_num_old = file_num_old - 1
            end
        end

    end
    return 0
end

function timer_event(ns)
    -- no op
end

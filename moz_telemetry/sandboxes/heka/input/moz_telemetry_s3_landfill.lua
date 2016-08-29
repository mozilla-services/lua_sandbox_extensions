-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry Landfill Data S3 Input

Retrieves/reads each file from the `s3_file_list`. The primary use of this
sandbox is to backfill the telemetry folder or to test new data
transformation/validation sandboxes.

## Sample Configuration
```lua
filename        = "moz_telemetry_s3_landfill.lua"
s3_bucket       = "net-mozaws-prod-us-west-2-pipeline-data"
s3_file_list    = "landfill_dims.ls.1"
tmp_dir         = "/mnt/work/tmp"
schema_path     = "./mozilla-pipeline-schemas"
passthru        = false -- if true the raw message is injected as-is (nginx_moz_ingest test)
```
--]]

require "io"
require "os"
require "string"

local tm
local tmp_dir       = read_config("tmp_dir")
local s3_bucket     = read_config("s3_bucket") or error("s3_bucket must be set")
local logger        = read_config("Logger")
local is_running    = is_running
if not read_config("passthru") then
    tm = require "moz_telemetry.extract_dimensions".transform_message
end


local s3_file_list  = assert(io.open(read_config("s3_file_list")))
local count         = 0

local function process_file(hsr, fn)
    local shutdown = false
    local fh, err =  io.open(fn)
    if not fh then
        print("failed to open", fn)
        return shutdown
    end

    local found, consumed, read
    repeat
        repeat
            found, consumed, read = hsr:find_message(fh)
            if found then
                count = count + 1
                if tm then
                    tm(hsr)
                else
                    inject_message(hsr)
                end
            end
        until not found
        shutdown = not is_running()
    until read == 0 or shutdown
    fh:close()
    return shutdown
end


local function execute_cmd(cmd, retries)
    local rv = 1
    for i=1, retries do
        rv = os.execute(cmd)
        if rv == 0 then
            break
        end
    end
    return rv
end


function process_message()
    local hsr = create_stream_reader("s3")

    for fn in s3_file_list:lines() do
        local tfn = string.format("%s/%s", tmp_dir, logger)
        local cmd = string.format("aws s3 cp s3://%s/%s %s", s3_bucket, fn, tfn)
        print("processing", cmd)
        local rv = execute_cmd(cmd, 3)
        if rv == 0 then
            if process_file(hsr, tfn) then break end
        else
            print("failed to execute rv:", rv, " cmd:", cmd)
        end
    end
    return 0, tostring(count)
end

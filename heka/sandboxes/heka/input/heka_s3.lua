-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Protobuf S3 Stream Reader Input

Retrieves/reads each file from the `s3_file_list`. The reader supports
uncompressed, gzip, or zstd compression. The primary use of this sandbox is to
playback data streams through analysis sandboxes.

## Sample Configuration
```lua
filename        = "heka_s3.lua"
s3_bucket       = "net-mozaws-prod-us-west-2-pipeline-data"
s3_file_list    = "files.ls.1"
tmp_dir         = "/mnt/work/tmp"
```
--]]

require "io"
require "os"
require "string"

local tmp_dir       = read_config("tmp_dir")
local s3_bucket     = read_config("s3_bucket") or error("s3_bucket must be set")
local logger        = read_config("Logger")
local s3_file_list  = assert(io.open(read_config("s3_file_list")))


local function process_file(hsr, fn)
    local fh, err = io.open(fn)
    if not fh then
        print("failed to open", fn)
        return
    end

    local found, consumed, read
    repeat
        repeat
            found, consumed, read = hsr:find_message(fh)
            if found then
                inject_message(hsr)
            end
        until not found
    until read == 0
    fh:close()
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
        local cmd
        local tfn = string.format("%s/%s", tmp_dir, logger)
        local ext = fn:match("%.([^.]-)$")
        if ext == "zst" then
            cmd = string.format("aws s3 cp s3://%s/%s - | zstd -d -c - > %s", s3_bucket, fn, tfn)
        elseif ext == "gz" then
            cmd = string.format("aws s3 cp s3://%s/%s - | gzip -d -c - > %s", s3_bucket, fn, tfn)
        else
            cmd = string.format("aws s3 cp s3://%s/%s %s", s3_bucket, fn, tfn)
        end

        print("processing", cmd)
        local rv = execute_cmd(cmd, 3)
        if rv == 0 then
            process_file(hsr, tfn, compression)
        else
            print("failed to execute rv:", rv, " cmd:", cmd)
        end
    end
    return 0
end

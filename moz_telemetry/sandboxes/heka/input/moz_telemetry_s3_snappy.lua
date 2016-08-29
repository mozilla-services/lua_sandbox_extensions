-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry Data S3 Input

Retrieves/reads each file from the `s3_file_list`. The primary use of this
sandbox is to feed the transformed/validated data into analysis plugins. Once
the snappy ugliness is removed (Bugzilla #1250218) the generalized 'heka_s3.lua'
input can be used instead.


## Sample Configuration
```lua
filename        = "moz_telemetry_s3_snappy.lua"
s3_bucket       = "net-mozaws-prod-us-west-2-pipeline-data"
s3_file_list    = "telemetry_dims.ls.1"
tmp_dir         = "/mnt/work/tmp"
```
--]]

require "io"
require "os"
require "snappy"
require "string"

local tmp_dir       = read_config("tmp_dir")
local s3_bucket     = read_config("s3_bucket") or error("s3_bucket must be set")
local logger        = read_config("Logger")
local s3_file_list  = assert(io.open(read_config("s3_file_list")))
local is_running    = is_running


local function snappy_decode(msgbytes)
    local ok, uc = pcall(snappy.uncompress, msgbytes)
    if ok then
        return uc
    end
    return msgbytes
end


local function process_snappy_ugliness(hsr, dhsr, fh)
    local shutdown = false
    local found, consumed, read
    repeat
        repeat
            found, consumed, read = hsr:find_message(fh, false) -- don't protobuf decode
            if found then
                local pbm = snappy_decode(hsr:read_message("raw"))
                local ok = pcall(dhsr.decode_message, dhsr, pbm)
                if ok then
                    inject_message(dhsr)
                end
            end
        until not found
        shutdown = not is_running()
    until read == 0 or shutdown
    return shutdown
end


local function process_file(hsr, fh)
    local shutdown = false
    local found, consumed, read
    repeat
        repeat
            found, consumed, read = hsr:find_message(fh)
            if found then
                inject_message(hsr)
            end
        until not found
        shutdown = not is_running()
    until read == 0 or shutdown
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
    local shutdown  = false
    local hsr       = create_stream_reader("s3")
    local dhsr      = create_stream_reader("snappy")

    for fn in s3_file_list:lines() do
        local cmd
        local tfn = string.format("%s/%s", tmp_dir, logger)
        local ext = fn:match("%.([^.]-)$")
        if ext == "zst" then
            cmd = string.format("aws s3 cp s3://%s/%s - | zstd -d -c - > %s", s3_bucket, fn, tfn)
        elseif ext == "gz" then
            cmd = string.format("aws s3 cp s3://%s/%s - | gzip -d -c - > %s", s3_bucket, fn, tfn)
        else
            ext = nil
            cmd = string.format("aws s3 cp s3://%s/%s %s", s3_bucket, fn, tfn)
        end

        print("processing", cmd)
        local rv = execute_cmd(cmd, 3)
        if rv == 0 then
            local fh, err = io.open(tfn)
            if not fh then
                print("failed to open", tfn)
                return 0
            end
            if ext then
                shutdown = process_file(hsr, fh)
            else
                shutdown = process_snappy_ugliness(hsr, dhsr, fh)
            end
            fh:close()
            if shutdown then break end
        else
            print("failed to execute rv:", rv, " cmd:", cmd)
        end
    end
    return 0
end

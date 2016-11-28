-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "io"
require "os"
require "string"

--[[
# Near Real-Time Report Output and Optional S3 Sync

Outputs the real-time report to the configured directory. The output filename is
output_dir/Fields[day]/EnvVersion-logger.Fields[name].Fields[ext]
and the contents are Fields[data].

## Sample Configuration
```lua
filename        = "near_real_time_report.lua"
message_matcher = "Type == 'report.daily'"
ticker_interval = 60 -- aggregate reports are generally output every minute

-- location where the data is written (e.g. make them accessible from a web
-- server for external consumption)
output_dir      = "/var/tmp/hindsight/reports"

-- optional
s3_uri = "s3://example/reports"
s3_storage_class = STANDARD -- REDUCED_REDUNDANCY or STANDARD_IA
```
--]]

local output_dir        = read_config("output_dir") or "/var/tmp/hindsight/reports"
local install_path      = read_config("sandbox_install_path")
local s3_uri            = read_config("s3_uri")
local s3_storage_class  = read_config("s3_storage_class") or "STANDARD"
if s3_storage_class ~= "STANDARD" and
   s3_storage_class ~= "REDUCED_REDUNDANCY" and 
   s3_storage_class ~= "STANDARD_IA" then
     error("s3_storage_class must be STANDARD, REDUCED_REDUNDANCY or STANDARD_IA")
end

local function mkdir(path)
    local cmd = string.format("mkdir -p %s", path)
    local ret = os.execute(cmd)
    if ret ~= 0 then
        error(string.format("mkdir ret: %d, cmd: %s", ret, cmd))
    end
end
mkdir(output_dir)

local data = read_message("Fields[data]", nil, nil, true)
function process_message()
    local day = tostring(read_message("Fields[day]"))
    if not day:match("^%d%d%d%d%-%d%d%-%d%d$") then
        day = "1970-01-01"
    end

    local logger  = read_message("Logger") or "UNKNOWN"
    local version = read_message("EnvVersion") or "0"
    local name    = tostring(read_message("Fields[name]") or "UNKNOWN")
    local ext     = tostring(read_message("Fields[ext]")  or "")

    logger = string.gsub(logger, "[^%w%.]", "_")
    version = string.gsub(version, "[^%d%.]", "_")
    name = string.gsub(name, "[^%w%.]", "_")
    ext  = string.gsub(ext , "%W", "_")
    local path = string.format("%s/%s", output_dir, day)
    local fqfn = string.format("%s/%s-%s.%s.%s", path, version, logger, name, ext)

    local fh, err = io.open(fqfn, "w")
    if err then
        mkdir(path)
        fh, err = io.open(fqfn, "w")
        if err then return -1, err end
    end

    fh:write(data)
    fh:close()
    return 0
end

function timer_event(ns)
    if s3_uri then
        local cmd = string.format("aws s3 sync --storage-class %s %s %s",
                                  s3_storage_class, output_dir, s3_uri)
        local ret = os.execute(cmd)
        if ret ~= 0 then
            print(string.format("sync failed - ret: %d, cmd: %s", ret, cmd))
        end
    end
end

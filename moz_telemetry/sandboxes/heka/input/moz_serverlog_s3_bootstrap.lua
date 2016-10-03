-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Server Log Data S3 Input Sandbox Bootstrapper

This sandbox:

1. retrieves a list of files from S3 matching the `service` log name and the date range
1. divides the list among the specified number of `partitions`
1. generates the cfgs to dynamically start a new reader for each partition;
   the specified `input_plugin` should already be installed in run/input
1. exits when the bootstrapping is complete

## Sample Configuration
```lua
filename            = "moz_serverlog_s3_bootstrap.lua"
instruction_limit   = 0
ticker_interval     = 0

input_plugin        = "heka_s3.lua"
input_plugin_cfgs   = {} -- table of sandbox specific config options
tmp_dir             = "/mnt/work/tmp"
s3_bucket           = "heka-logs"
s3_prefix           = "shared"
start_date          = "2016-04-01"
end_date            = "2016-04-07"
service             = "loop-app"
partitions          = 1
```
--]]

require "io"
require "os"
require "string"

local input_plugin      = read_config("input_plugin")
local input_plugin_cfgs = read_config("input_plugin_cfgs") or {}
local tmp_dir           = read_config("tmp_dir")
local s3_bucket         = read_config("s3_bucket") or error("s3_bucket must be set")
local s3_prefix         = read_config("s3_prefix")
local service           = read_config("service") or error("service must be set")
local start_date        = read_config("start_date")
local end_date          = read_config("end_date")
local sblp              = read_config("sandbox_load_path")
local partitions        = tonumber(read_config("partitions"))
local list_file         = string.format("%s/%s.ls", tmp_dir, service)
local tmp_file          = string.format("%s/%s.tmp", tmp_dir, service)

if not partitions or partitions < 1 then error("partitions must be set > 0") end

local DATE_FORMAT           = "^(%d%d%d%d)%-(%d%d)%-(%d%d)$"
local syear, smonth, sday   = start_date:match(DATE_FORMAT)
start_date                  = os.time({year = syear, month = smonth, day = sday})

local eyear, emonth, eday   = end_date:match(DATE_FORMAT)
end_date                    = os.time({year = eyear, month = emonth, day = eday})
assert(end_date >= start_date, "end_date must be greater than or equal to the start_date")

local num_months = (eyear * 12 + emonth) - (syear * 12 + smonth)


local function partition_list()
    local fhs = {}
    for i=1, partitions do
        fhs[i] = assert(io.open(string.format("%s.%d", list_file, i), "w"))
    end

    local cnt = 0
    for line in io.lines(list_file) do
        local idx = cnt % partitions + 1
        fhs[idx]:write(line, "\n")
        cnt = cnt + 1
    end

    for i=1, partitions do
        fhs[i]:close()
    end
end


local function dump_table(fh, t, sep)
    for k,v in pairs(t) do
        if type(v) == "table" then
            fh:write(string.format("%s = {\n", k))
            dump_table(fh, v, ",")
            fh:write(string.format("}%s\n", sep))
        else
            if type(v) == "string" then
                fh:write(string.format("%s = [=[%s]=]%s\n", k, v, sep))
            else
                fh:write(string.format("%s = %s%s\n", k, tostring(v), sep))
            end
        end
    end
end


local function load_plugins()
    local fhs = {}
    for i=1, partitions do
        local partition_file = string.format("%s.%d", list_file, i)
        local lua_cfg = string.format("%s/input/%s%02d.cfg", sblp, service, i)
        local fh = assert(io.open(lua_cfg, "w"))
        fh:write(string.format("filename     = '%s'\n", input_plugin))
        fh:write(string.format("s3_bucket    = '%s'\n", s3_bucket))
        fh:write(string.format("s3_file_list = '%s'\n", partition_file))
        fh:write(string.format("tmp_dir      = '%s'\n\n", tmp_dir))
        dump_table(fh, input_plugin_cfgs, "") -- put the values in the root
        fh:close()
    end
end


local function get_listing(fh, year, month)
    local path
    if s3_prefix then
        path = string.format("%s/%04d-%02d", s3_prefix, year, month)
    else
        path = string.format("%04d-%02d", year, month)
    end

    local cmd = string.format("aws s3 ls s3://%s/%s/ > %s", s3_bucket, path, tmp_file)
    print(cmd)
    local rv = os.execute(cmd)
    if rv ~= 0 and rv ~= 256 then
        error(string.format("error executing rv: %d cmd: %s", rv, cmd))
    end

    local tfh = assert(io.open(tmp_file))
    for line in tfh:lines() do
        local fn, ds = string.match(line, "^%d%d%d%d%-%d%d%-%d%d%s+%d%d:%d%d:%d%d%s+%d+%s+(.-%-(%d%d%d%d%d%d%d%d)_.+)")
        if ds then
            ds = os.time({year = ds:sub(1, 4), month = ds:sub(5, 6), day = ds:sub(7, 8)})
            if fn and string.find(fn, service, 1, true) and ds >= start_date and ds <= end_date then
                fh:write(path, "/", fn, "\n")
            end
        end
    end
    tfh:close()
end


function process_message()
    local fh = assert(io.open(list_file, "w"))
    local year = tonumber(syear)
    local month = tonumber(smonth)
    for i=0, num_months do
        get_listing(fh, year, month)
        month = month + 1
        if month == 13 then
            month = 1
            year  = year + 1
        end
    end
    fh:close()

    os.remove(tmp_file)
    partition_list()
    load_plugins()
    return 0
end

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Telemetry Data S3 Input Sandbox Bootstrapper

This sandbox:

1. retrieves a list of files from S3 matching the dimension specification
   in `dimension_file`
1. divides the list among the specified number of `partitions`
1. generates the cfgs to dynamically start a new reader for each partition;
   the specified `input_plugin` should already be installed in run/input
1. exits when the bootstrapping is complete

## Sample Configuration
```lua
filename            = "moz_telemetry_s3_bootstrap.lua"
instruction_limit   = 0
ticker_interval     = 0

input_plugin        = "telemetry_s3_snappy.lua"
input_plugin_cfgs   = {} -- table of sandbox specific config options
tmp_dir             = "/mnt/work/tmp"
s3_bucket           = "net-mozaws-prod-us-west-2-pipeline-data"
s3_prefix           = "telemetry-2"
dimension_file      = "dimensions.json"
partitions          = 8
```
--]]

require "io"
require "os"
require "string"
require "table"
local mts3 = require "moz_telemetry.s3"

local input_plugin      = read_config("input_plugin")
local input_plugin_cfgs = read_config("input_plugin_cfgs") or {}
local tmp_dir           = read_config("tmp_dir")
local s3_bucket         = read_config("s3_bucket") or error("s3_bucket must be set")
local s3_prefix         = read_config("s3_prefix")
local sblp              = read_config("sandbox_load_path")
local dim_file          = read_config("dimension_file")
local dimensions        = mts3.validate_dimensions(dim_file)
local dimensions_size   = #dimensions
local partitions        = tonumber(read_config("partitions"))
if not partitions or partitions < 1 then error("partitions must be set > 0") end

local dim_name          = dim_file:match("/?([^/]+)$") -- grab the filename
dim_name                = dim_name:match("(.+)%.") or dim_name -- strip any extension
local list_file         = string.format("%s/%s.ls", tmp_dir, dim_name)
local tmp_file          = string.format("%s/%s.tmp", tmp_dir, dim_name)
local LINE_MATCH        = "^%d%d%d%d%-%d%d%-%d%d%s+%d%d:%d%d:%d%d%s+%d+%s+(.+)"


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
            fh:write(string.format("%s = {\n", k, v))
            dump_table(fh, v, ",")
            fh:write(string.format("}%s\n", sep))
        else
            fh:write(string.format("%s = [[%s]]%s\n", k, v, sep))
        end
    end
end


local function load_plugins()
    local fhs = {}
    for i=1, partitions do
        local partition_file = string.format("%s.%d", list_file, i)
        local lua_cfg = string.format("%s/input/%s%02d.cfg", sblp, dim_name, i)
        local fh = assert(io.open(lua_cfg, "w"))
        fh:write(string.format("filename     = '%s'\n", input_plugin))
        fh:write(string.format("s3_bucket    = '%s'\n", s3_bucket))
        fh:write(string.format("s3_file_list = '%s'\n", partition_file))
        fh:write(string.format("tmp_dir      = '%s'\n\n", tmp_dir))
        dump_table(fh, input_plugin_cfgs, "") -- put the values in the root
        fh:close()
    end
end


function process_message()
    local fh = assert(io.open(list_file, "w"))
    build_path(fh, {}, 1)
    fh:close()

    os.remove(tmp_file)
    partition_list()
    load_plugins()
    return 0
end


function build_path(fh, prefix, level)
    if level > dimensions_size then
        get_listing(fh, prefix, level)
        return
    end

    local d = dimensions[level]
    if d.matcher_type == "wildcard" or d.matcher_type == "minmax" then
        get_listing(fh, prefix, level)
    elseif d.matcher_type == "string" then
        prefix[#prefix + 1] = d.allowed_values
        build_path(fh, prefix, level + 1)
        table.remove(prefix)
    elseif d.matcher_type == "list" then
        for i, v in ipairs(d.allowed_values) do
            prefix[#prefix + 1] = v
            build_path(fh, prefix, level + 1)
            table.remove(prefix)
        end
    end
end


function get_listing(fh, prefix, level)
    local is_recursive  = dimensions[level] and dimensions[level].matcher_type == "wildcard"
    local path          = table.concat(prefix, "/")
    local cmd
    if s3_prefix then
        cmd = string.format("aws s3 ls %s s3://%s/%s/%s/ > %s",
                            is_recursive and "--recursive" or "",
                            s3_bucket, s3_prefix, path, tmp_file)
    else
        cmd = string.format("aws s3 ls %s s3://%s/%s/ > %s",
                            is_recursive and "--recursive" or "",
                            s3_bucket, path, tmp_file)
    end

    print(cmd)
    local rv = os.execute(cmd)
    if rv ~= 0 and rv ~= 256 then
        error(string.format("error executing rv: %d cmd: %s", rv, cmd))
    end

    local tfh = assert(io.open(tmp_file))
    if is_recursive then -- get the entire set of files in the tree
        for line in tfh:lines() do
            local fn = string.match(line, LINE_MATCH)
            if fn then
                local cnt = 0
                local keep = true
                for dim in string.gmatch(fn, "[^/]+") do
                    if cnt > level then
                        for i=cnt, dimensions_size do
                            if not dimensions[cnt].matcher(dim) then
                                keep = false
                                break
                            end
                        end
                    end
                    if not keep then break end
                    cnt = cnt + 1
                end
                if keep then fh:write(fn, "\n") end
            end
        end
    elseif level > dimensions_size then -- get the files in the last prefix
        for line in tfh:lines() do
            local fn = string.match(line, LINE_MATCH)
            if fn then
                if s3_prefix then
                    fh:write(s3_prefix, "/", path, "/", fn, "\n")
                else
                    fh:write(path, "/", fn, "\n")
                end
            end
        end
    else -- match prefixes
        local matcher = dimensions[level].matcher
        for line in tfh:lines() do
            local pre = line:match("PRE%s+([^/]+)/")
            if pre then
                 if matcher(pre) then
                    prefix[#prefix + 1] = pre
                    build_path(prefix, level + 1)
                    table.remove(prefix)
                end
            end
        end
    end
    tfh:close()
end

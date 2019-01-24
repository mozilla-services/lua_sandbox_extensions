-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Protobuf Message S3 Output Partitioner

Batches message data into Heka protobuf stream files based on the specified path
dimensions and copies them to S3 when they reach the maximum size or maximum
age.

#### Sample Configuration

```lua
filename        = "moz_telemetry_s3.lua"
message_matcher = "Type == 'telemetry'"
ticker_interval = 60

-- see the moz_telemetry.s3 module
dimension_file  = "test.json"

-- https://bugzilla.mozilla.org/show_bug.cgi?id=1353110
experiment_dimension_file  = "test_experiments.json" -- optional

-- directory location to store the intermediate standard output files
batch_dir       = "/var/tmp/foobar"

-- directory location to store the intermediate experiment output files
experiment_batch_dir       = "/var/tmp/experiment"

-- Specifies how many data files to keep open at once. If there are more
-- "current" files than this, the least-recently used file will be closed
-- and then re-opened if more messages arrive before it is copied to S3. The
-- default is 1000. A value of 0 means no maximum.
max_file_handles    = 1000

-- Specifies how much data (in bytes) can be written to a single file before
-- it is finalized (default 300MiB)
max_file_size       = 1024 * 1024 * 300

-- Specifies how long (in seconds) to wait before the file is finalized
-- (default 1 hour).  Idle files are only checked every ticker_interval seconds.
max_file_age        = 60 * 60

-- Specifies that all local files will finalized before exiting (default false).
-- When streaming compression is used the file will always be finalized on exit.
flush_on_shutdown   = true
preserve_data       = not flush_on_shutdown -- should always be the inverse of flush_on_shutdown

-- Specify an optional module to encode incoming messages via its encode function.
-- encoder_module = "encoders.heka.framed_protobuf" -- default

-- Specifies experiment types whitelist, and experiment id blocklist
experiment_types = {["normandy-preference-"] = true} -- optional
experiment_blocklist = {["pref-flip-screenshots-release-1369150"] = true} -- optional
```
--]]

require "cjson"
require "io"
require "os"
require "string"
require "table"
local mts3 = require "moz_telemetry.s3"

files               = {}
local fh_cnt        = 0
local time_t        = 0
local buffer_cnt    = 0

local hostname          = read_config("Hostname")
local hostname_len      = #hostname
local batch_dir         = read_config("batch_dir") or error("batch_dir must be specified")
local experiment_batch_dir
local max_file_handles  = read_config("max_file_handles") or 1000
local max_file_size     = read_config("max_file_size") or 1024 * 1024 * 300
local max_file_age      = read_config("max_file_age") or 60 * 60
local flush_on_shutdown = read_config("flush_on_shutdown")
local compression       = read_config("compression")
assert(not compression, "compression is no longer supported")

local encoder_module = read_config("encoder_module") or "encoders.heka.framed_protobuf"
local encode = require(encoder_module).encode
if not encode then
    error(encoder_module .. " does not provide an encode function")
end
local dimensions = mts3.validate_dimensions(read_config("dimension_file"))
local experiment_dimensions = read_config("experiment_dimension_file")
if experiment_dimensions then
    experiment_batch_dir  = read_config("experiment_batch_dir") or error("experiment_batch_dir must be specified")
    experiment_dimensions = mts3.validate_dimensions(experiment_dimensions)
end
local experiment_types = read_config("experiment_types") or {}
assert(type(experiment_types) == "table", "experiment_types must be a table")
local experiment_blocklist = read_config("experiment_blocklist") or {}
assert(type(experiment_blocklist) == "table", "experiment_blocklist must be a table")


local function get_fqfn(dir, path)
    return string.format("%s/%s", dir, path)
end


local function close_fh(entry)
    if not entry[2] then return end
    entry[2]:close()
    entry[2] = nil
    fh_cnt = fh_cnt - 1
end


local function rename_file(path, entry)
    close_fh(entry)
    local t = os.time()
    local cmd
    if t == time_t then
        buffer_cnt = buffer_cnt + 1
    else
        time_t = t
        buffer_cnt = 0
    end

    local src = get_fqfn(entry[4], path)
    local dest = string.format("%s+%d_%d_%s.done", src, time_t, buffer_cnt, hostname)

    local ok, err = os.rename(src, dest)
    if not ok then
        error(string.format("os.rename('%s','%s') failed: %s", src, dest, err))
    end
    files[path] = nil
end


local function get_entry(dir, path)
    local ct = os.time()
    local t = files[path]
    if not t then
        -- last active, file handle, creation time, output_dir
        t = {ct, nil, ct, dir}
        files[path] = t
    else
        t[1] = ct
    end

    if not t[2] then
        if max_file_handles ~= 0 then
            if fh_cnt >= max_file_handles then
                local oldest = ct + 60
                local entry
                -- if we max out file handles a lot we will want to make this more efficient
                for k,v in pairs(files) do
                    local et = v[1]
                    if v[2] and et < oldest then
                        entry = v
                        oldest = et
                    end
                end
                if entry then close_fh(entry) end
            end
        end
        t[2] = assert(io.open(get_fqfn(dir, path), "a"))
        fh_cnt = fh_cnt + 1
    end
    return t
end


local function mkdir(dir)
    local cmd = string.format("mkdir -p %s", dir)
    local ret = os.execute(cmd)
    if ret ~= 0 then
        error(string.format("ret: %d, cmd: %s", ret, cmd))
    end
end

mkdir(batch_dir)
if experiment_batch_dir then mkdir(experiment_batch_dir) end


local function output_dimension(dir, dims, data)
    local path = table.concat(dims, "+") -- the plus will be converted to a path separator '/' on copy
    -- leave room for the suffix e.g. "+1548192798_000_<hostname>.done"
    if #path + hostname_len + 21 > 255 then
        return "filename too long", path
    end

    local entry = get_entry(dir, path)
    local fh = entry[2]

    fh:write(data)
    local size = fh:seek()
    if size >= max_file_size then
        rename_file(path, entry)
    end
end


local function process_standard_dimensions(data)
    local dims = {}
    for i,d in ipairs(dimensions) do
        dims[i] = mts3.read_dimension(d)
    end
    return output_dimension(batch_dir, dims, data)
end


local function does_experiment_qualify(id, branch, experimentType)
    return (not experimentType or experiment_types[experimentType])
        and not experiment_blocklist[id]
end


local function process_experiment_dimensions(data, experiments)
    local ok, experiments = pcall(cjson.decode, experiments)
    if not ok then return end

    local vars = {}
    for id, exp in pairs(experiments) do
        vars.experimentId = id
        vars.experimentBranch = exp.branch
        if does_experiment_qualify(id, exp.branch, exp.type) then
            local dims = {}
            for i,d in ipairs(experiment_dimensions) do
                dims[i] = mts3.read_dimension(d, vars)
            end
            -- silently ignore errors since we don't have a concept of a partial
            -- error and the standard dimension output was successful
            local err, path = output_dimension(experiment_batch_dir, dims, data)
            if err then print(err, path) end
        end
    end
end


function process_message()
    local ok, data = pcall(encode)
    if not ok then return -1, data end
    if not data then return -2 end

    local err, path = process_standard_dimensions(data)
    if err then return -1, err .. ": " .. path end

    if experiment_dimensions then
        local experiments = read_message("Fields[environment.experiments]")
        if experiments then
            process_experiment_dimensions(data, experiments)
        end
    end
    return 0
end


function timer_event(ns, shutdown)
    local ct = os.time()
    for k,v in pairs(files) do
        if (shutdown and flush_on_shutdown) or (ct - v[3] >= max_file_age) then
            rename_file(k, v)
        elseif shutdown then
            close_fh(v)
        end
    end
end

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# S3 Output Partitioner/Parquet output

Batches message data into Parquet files based on the specified S3 path
dimensions and copies them to S3 when they reach the maximum size or maximum
age. **Note:** For now this plugin renames the file to "*.done" and a separate
process takes care of the S3 upload.

#### Sample Configuration

```lua
filename        = "s3_parquet.lua"
message_matcher = "Type == 'telemetry' && Fields[docType] == 'main'"
ticker_interval = 60
preserve_data   = false

parquet_schema = [=[
message environment_build {
    required binary applicationName;
    required binary architecture;
    required binary buildId;
    required binary version;
    required binary vendor;
}
]=]

-- Heka message varible containing a JSON string. The docoded JSON record
-- is dissected based on the parquet schema.
json_variable = "Fields[environment.build]"

s3_path_dimensions  = {
    {name = "submission_date", source = "Fields[submissionDate]"},
    {name = "doc_type", source = "Fields[docType]"},
    {name = "normalized_channel", source = "Fields[normalizedChannel]"},
    {name = "os", source="Fields[os]"},
    {name = "application_name", source = "Fields[appName]"},
    -- grabs the applicationName from the JSON structure in "json_variable"
    -- this can be used if the data does not exist in a Heka message variable.
    -- The source element is an array of key names/array indexes traversing the
    -- structure hierarchy to the leaf data node.
    --{name = "application_name", source = {"applicationName"}}
}

-- directory location to store the intermediate output files
batch_dir       = "/var/tmp/parquet"

-- Specifies how many parquet writers can be opened at once. If this value is
-- exceeded the least-recently used writer will have its data finalize and be
-- closed. The default is 100. A value of 0 means no maximum **warning** if
-- there are a large number of partitions this can easily run the system out of
-- file handles and/or memory.
max_writers         = 100

-- Specifies how many records to aggregate before creating a rowgroup
-- (default 10000)
max_rowgroup_size   = 10000

-- Specifies how much data (in bytes) can be written to a single file before
-- it is finalized. The file size is only checked after each rowgroup write
-- (default 300MiB).
max_file_size       = 1024 * 1024 * 300

-- Specifies how long (in seconds) to wait before the file is finalized
-- (default 1 hour).  Idle files are only checked every ticker_interval seconds.
max_file_age        = 60 * 60

hive_compatible     = false

```
--]]

require "cjson"
require "io"
require "os"
require "parquet"
local load_schema = require "lpeg.parquet".load_parquet_schema
require "string"
require "table"

local writers       = {}
local writers_cnt   = 0
local buffer_cnt    = 0
local time_t        = 0

local hostname              = read_config("Hostname")
local parquet_schema        = read_config("parquet_schema") or error("parquet_schema must be specified")
local json_variable         = read_config("json_variable") or error("json_variable must be specified")
local s3_path_dimensions    = read_config("s3_path_dimensions") or error("s3_path_dimensions must be specified")
local batch_dir             = read_config("batch_dir") or error("batch_dir must be specified")
local max_writers           = read_config("max_writers") or 100
local max_rowgroup_size     = read_config("max_rowgroup_size") or 10000
local max_file_size         = read_config("max_file_size") or 1024 * 1024 * 300
local max_file_age          = read_config("max_file_age") or 60 * 60
local hive_compatible       = read_config("hive_compatible")

local default_nil  = "UNKNOWN"
if hive_compatible then
    default_nil = "__HIVE_DEFAULT_PARTITION__"
    -- todo set hive compatibility in the parquet module when available
end
parquet_schema = load_schema(parquet_schema)


local function get_fqfn(path)
    return string.format("%s/%s", batch_dir, path)
end


local function close_writer(path, writer)
    writer[1]:close()
    local t = os.time()
    local cmd
    if t == time_t then
        buffer_cnt = buffer_cnt + 1
    else
        time_t = t
        buffer_cnt = 0
    end

    local src = get_fqfn(path)
    local dest = string.format("%s+%d_%d_%s.done", src, time_t, buffer_cnt, hostname)

    local ok, err = os.rename(src, dest)
    if not ok then
        error(string.format("os.rename('%s','%s') failed: %s", src, dest, err))
    end
    writers[path] = nil
    writers_cnt = writers_cnt - 1
end


local function get_writer(path)
    local ct = os.time()
    local writer = writers[path]
    if not writer then
        -- writer, creation_time, last_active, record_cnt
        local src = get_fqfn(path)
        writer = {parquet.writer(src, parquet_schema), ct, ct, 0}
        writers[path] = writer
        writers_cnt = writers_cnt + 1
    else
        writer[3] = ct
    end

    if max_writers ~= 0 then
        if writers_cnt >= max_writers then
            local oldest = ct + 60
            local oldest_path
            local oldest_writer
            -- if we max out writers a lot we will want to make this more efficient
            for k,v in pairs(writers) do
                local et = v[3]
                if et < oldest then
                    oldest = et
                    oldest_path = k
                    oldest_writer = v
                end
            end
            if oldest_writer then close_writer(oldest_path, oldest_writer) end
        end
    end
    return writer
end

-- create the batch directory if it does not exist
local cmd = string.format("mkdir -p %s", batch_dir)
local ret = os.execute(cmd)
if ret ~= 0 then
    error(string.format("ret: %d, cmd: %s", ret, cmd))
end


local function read_json(json, path)
    local len = #path
    local v = json
    for i=1, len do
        v = v[path[i]]
        local t = type(v)
        if t == "nil" or (t ~= "table" and i ~= len) or (t == "table" and i == len) then
            return nil
        end
    end
    return tostring(v)
end


local function get_s3_path(json)
    local dims = {}
    local v
    for i,d in ipairs(s3_path_dimensions) do
        if type(d.source) == "string" then
            v = read_message(d.source) or default_nil
        else
            v = read_json(json, d.source) or default_nil
        end
        dims[i] = string.format("%s=%s", d.name, string.gsub(v, "[^%w!%-_.*'()]", "-"))
    end
    return table.concat(dims, "+") -- the plus will be converted to a path separator '/' when uploaded to S3
end


function process_message()
    local ok, json = pcall(cjson.decode, read_message(json_variable))
    if not ok then return -1, json end

    local path = get_s3_path(json)
    local writer = get_writer(path)
    local w = writer[1]
    local ok, err = pcall(w.dissect_record, w, json)
    if not ok then return -1, err end

    local record_cnt = writer[4] + 1
    writer[4] = record_cnt

    if record_cnt >= max_rowgroup_size then
        w:write_rowgroup()
        writer[4] = 0
        -- todo we may want to create a dependency on LFS so we can just stat the file
        local src = get_fqfn(path)
        local fh = assert(io.open(src))
        local file_size = fh:seek("end")
        fh:close()
        if file_size >= max_file_size then
            close_writer(path, writer)
        end
    end
    return 0
end


function timer_event(ns, shutdown)
    local ct = os.time()
    for path, writer in pairs(writers) do
        if shutdown or (ct - writer[2] >= max_file_age) then
            close_writer(path, writer)
        end
    end
end

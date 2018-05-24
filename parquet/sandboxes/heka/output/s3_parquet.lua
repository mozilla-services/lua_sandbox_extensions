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
message_matcher = "Type == 'telemetry' && Fields[docType] == 'testpilot'"
ticker_interval = 60
preserve_data   = false

parquet_schema = [=[
    message testpilot {
        required binary id (UTF8);
        optional binary clientId (UTF8);
        required group metadata {
            required int64  Timestamp;
            required binary submissionDate (UTF8);
            optional binary Date (UTF8);
            optional binary normalizedChannel (UTF8);
            optional binary geoCountry (UTF8);
            optional binary geoCity (UTF8);
        }
        optional group application {
            optional binary name (UTF8);
        }
        optional group environment {
            optional group system {
                optional group os {
                    optional binary name (UTF8);
                    optional binary version (UTF8);
                }
            }
        }
        optional group payload {
            optional binary version (UTF8);
            optional binary test (UTF8);
            repeated group events {
                optional int64  timestamp;
                optional binary event (UTF8);
                optional binary object (UTF8);
            }
        }
    }
]=]

-- optionally load the schema from disk instead of specifying `parquet_schema` (not allowed from the admin UI)
-- parquet_schema_file = "/usr/share/mozilla-pipeline-schemas/telemetry/new-profile/new-profile.4.parquetmr.txt"

-- The name of a top level parquet group used to specify additional information
-- to be extracted from the message (using read_message). If the column name
-- matches a Heka message header name the data is extracted from 'msg.name'
-- otherwise the data is extracted from msg.Fields[name]
metadata_group = "metadata"
-- metadata_prefix = nil -- if this is set any root level schema object
                         -- containing this prefix will be treated as metadata

-- Array of Heka message variables containing JSON strings. The decoded JSON
-- objects are assembled into a record that is dissected based on the parquet
-- schema. This provides a generic way to cherry pick and re-combine the
-- segmented JSON structures like the Mozilla telemetry pings. A table can be
-- passed as the first value either empty or with some pre-seeded values.
-- If not specified the schema is applied directly to the Heka message.
json_objects = {"Fields[submission]", "Fields[environment.system]"}

s3_path_dimensions  = {
    -- access message data with using read_message()
    {name = "_submission_date", source = "Fields[submissionDate]"},
    -- access Timestamp using read_message() and then encode it using the dateformat string.
    -- scaling_factor is multiplied by source to output timestamp seconds. The default is 1e-9,
    -- which implies that source is in nanoseconds.
    {name = "_submission_date", source = "Timestamp", dateformat = "%Y-%m-%d-%H", scaling_factor = 1e-9},
    -- access the record data with a path array
    -- {name = "_submission_date", source = {"metadata", "submissionDate"}}
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

-- This option causes the field name to be converted to a hive compatible column
-- name in the parquet output. The conversion snake cases the field name and
-- replaces any non [-_a-z0-9] characters with an underscore.
-- e.g. FooBar? -> foo_bar_
hive_compatible     = true -- default false

```
--]]

require "io"
require "os"
require "parquet"
local load_schema = require "lpeg.parquet".load_parquet_schema
require "string"
require "table"
local date = require "os".date

local writers       = {}
local writers_cnt   = 0
local buffer_cnt    = 0
local time_t        = 0

local hindsight_admin   = read_config("hindsight_admin")
local hostname          = read_config("Hostname")
local metadata_group    = read_config("metadata_group")
local metadata_prefix   = read_config("metadata_prefix")
local json_objects      = read_config("json_objects")
local json_decode_null  = read_config("json_decode_null")
local json_objects_len  = 0
if type(json_objects) == "table" then
    require "cjson"
    if json_decode_null then
       cjson.decode_null(true)
    end
    json_objects_len = #json_objects
end
if not json_objects and metadata_group then error("metadata_group cannot be configured without json_objects") end

local function load_schema_file()
    local schema
    if not hindsight_admin then
        local psf = read_config("parquet_schema_file") or error("parquet_schema_file must be specified")
        if psf then
            local fh = assert(io.open(psf))
            schema = fh:read("*a")
            fh:close()
        end
    end
    return schema
end

local parquet_schema        = read_config("parquet_schema") or load_schema_file() or error("parquet_schema must be specified")
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
end
parquet_schema, load_metadata = load_schema(parquet_schema, hive_compatible, metadata_group, metadata_prefix)


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
    local dest
    if hindsight_admin then
        dest = string.format("%s/%s.parquet", batch_dir, read_config("Logger")) -- only save off one for debugging
    else
        dest = string.format("%s+%d_%d_%s.done", src, time_t, buffer_cnt, hostname)
    end

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
        if d.dateformat then
            v = date(d.dateformat, v*(d.scaling_factor or 1e-9))
        end
        dims[i] = string.format("%s=%s", d.name, string.gsub(v, "[^%w!%-_.*'()]", "-"))
    end
    return table.concat(dims, "+") -- the plus will be converted to a path separator '/' when uploaded to S3
end


local function load_json_objects()
    local ok, root, record
    for i=1, json_objects_len do
        local k = json_objects[i]
        if type(k) == "table" and i == 1 then
            record = k
        else
            ok, record = pcall(cjson.decode, read_message(k))
            if not ok then return nil, record end
        end

        if not root then
            root = record
        else
            if k:match("^Fields%[") then
                k = k:sub(8, #k - 1)
            end
            local cur = root
            for w, more in string.gmatch(k, "([^.]+)(%.?)") do
                if more == "." then
                    local t = cur[w]
                    if not t then
                        t = {}
                        cur[w] = t
                    end
                    cur = t
                else
                    cur[w] = record
                end
            end
        end
    end
    return root, nil
end

function process_message()
    local ok, err, record
    if json_objects then
        record, err = load_json_objects()
        if err then return -1, err end
        if load_metadata then load_metadata(record) end
    end

    local path = get_s3_path(record)
    local writer = get_writer(path)
    local w = writer[1]

    if json_objects then
        ok, err = pcall(w.dissect_record, w, record)
    else
        ok, err = pcall(w.dissect_message, w)
    end
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

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
dimension_file  = "foobar.json"

-- directory location to store the intermediate output files
batch_dir       = "/var/tmp/foobar"

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

compression         = "gz"

-- Specify an optional module to encode incoming messages via its encode function.
encoder_module = nil
```
--]]

require "io"
require "os"
require "string"
require "table"
local mts3 = require "moz_telemetry.s3"

files               = {}
local fh_cnt        = 0
local time_t        = 0
local buffer_cnt    = 0

local hostname              = read_config("Hostname")
local batch_dir             = read_config("batch_dir") or error("batch_dir must be specified")
local max_file_handles      = read_config("max_file_handles") or 1000
local max_file_size         = read_config("max_file_size") or 1024 * 1024 * 300
local max_file_age          = read_config("max_file_age") or 60 * 60
local flush_on_shutdown     = read_config("flush_on_shutdown")
local compression           = read_config("compression")
if compression and compression ~= "gz" then
    error("compression must be nil or gz")
end

if compression == "gz" then
    require "zlib"
end

local encoder_module        = read_config("encoder_module")
local encode                = false
if encoder_module then
    encode = require(encoder_module).encode
    if not encode then
        error(encoder_module .. " does not provide a encode function")
    end
end

local function get_fqfn(path)
    return string.format("%s/%s", batch_dir, path)
end


local function close_fh(entry)
    if not entry[2] then return end
    entry[2]:close()
    entry[2] = nil
    fh_cnt = fh_cnt - 1
end


local function rename_file(path, entry)
    if compression == "gz" then
        local def, eof, bin, bout = entry[4]() -- finalize the compressed stream
        if #def > 0 then
            if not entry[2] then
                entry[2] = assert(io.open(get_fqfn(path), "a"))
            end
            entry[2]:write(def)
        end
    end

    close_fh(entry)
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
    if compression then
        dest = string.format("%s+%d_%d_%s.%s.done", src, time_t, buffer_cnt, hostname, compression)
    else
        dest = string.format("%s+%d_%d_%s.done", src, time_t, buffer_cnt, hostname)
    end

    local ok, err = os.rename(src, dest)
    if not ok then
        error(string.format("os.rename('%s','%s') failed: %s", src, dest, err))
    end
    files[path] = nil
end


local function get_entry(path)
    local ct = os.time()
    local t = files[path]
    if not t then
        if compression == "gz" then
            -- last active, file handle, creation time, compression function
            t = {ct, nil, ct, zlib.deflate(nil, 31)}
        else
            -- last active, file handle, creation time
            t = {ct, nil, ct}
        end
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
        t[2] = assert(io.open(get_fqfn(path), "a"))
        fh_cnt = fh_cnt + 1
    end
    return t
end

local dimensions = mts3.validate_dimensions(read_config("dimension_file"))
-- create the batch directory if it does not exist
local cmd = string.format("mkdir -p %s", batch_dir)
local ret = os.execute(cmd)
if ret ~= 0 then
    error(string.format("ret: %d, cmd: %s", ret, cmd))
end


function process_message()
    local dims = {}
    for i,d in ipairs(dimensions) do
        local v = mts3.sanitize_dimension(read_message(d.field_name))
        if v then
            if d.matcher(v) then
                dims[i] = v
            else
                dims[i] = "OTHER"
            end
        else
            dims[i] = "UNKNOWN"
        end
    end
    local path = table.concat(dims, "+") -- the plus will be converted to a path separator '/' on copy
    local entry = get_entry(path)
    local fh = entry[2]
    local encoded
    if encode then
        encoded = encode()
    else
        encoded = read_message("framed")
    end
    if not encoded then return 0 end

    if compression == "gz" then
        local def, eof, bin, bout = entry[4](encoded)
        if #def > 0 then
            fh:write(def)
        end
        if bout >= max_file_size then
            rename_file(path, entry)
        end
    else
        fh:write(encoded)
        local size = fh:seek()
        if size >= max_file_size then
            rename_file(path, entry)
        end
    end
    return 0
end


function timer_event(ns, shutdown)
    local ct = os.time()
    for k,v in pairs(files) do
        if (shutdown and (flush_on_shutdown or compression)) or (ct - v[3] >= max_file_age) then
            rename_file(k, v)
        elseif shutdown then
            close_fh(v)
        end
    end
end

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# GCP BigQuery Loader

Batches message data into new line delimited JSON or TSV files and loads them
into BigQuery when they reach the specified size or timeout.

#### Sample Configuration

```lua
filename                = "gcp_bigquery.lua"
message_matcher         = "Type == 'bigquery.json'"
ticker_interval         = 60
read_queue              = "input"
shutdown_on_terminate   = true

-- directory location to store the intermediate output files
batch_dir       = "/var/tmp" -- default

-- Specifies how much data (in bytes) can be written to a single file before
-- it is finalized.
max_file_size       = 1024 * 1024 * 1024 -- default

-- Specifies how long (in seconds) to wait before the file is finalized
-- Idle files are only checked every ticker_interval seconds.
max_file_age        = 3600 -- default
load_fail_cache     = 50 -- default number of files to save off for manual recovery
load_timeout        = nil -- default number of seconds before the load will be killed Issue #498
bq_dataset          = "test"
bq_table            = "demo"
--json_field        = "Payload" -- default should contain a single line of JSON with no new lines
--tsv_fields        = {"Timestamp", "Type", "Payload", "Fields[error_detail]", "Fields[data]"}

-- Specify a module that will encode/convert the Heka message into its output representation.
encoder_module = nil -- uses the standard behavior documented above

alert = {
  disabled = false,
  prefix = true,
  throttle = 0,
  modules = {
    email = {recipients = {"notify@example.com"}},
  },
}

```
--]]

local alert = require "heka.alert"
require "io"
require "os"
require "string"
require "table"

local batch_dir         = read_config("batch_dir") or "/var/tmp"
local max_file_size     = read_config("max_file_size") or 1024 * 1024 * 1024
local max_file_age      = read_config("max_file_age") or 3600
local load_fail_cache   = read_config("load_fail_cache") or 50
local load_timeout      = tonumber(read_config("load_timeout"))
local bq_dataset        = read_config("bq_dataset") or error"must specify bq_dataset"
local bq_table          = read_config("bq_table") or error"must specify bq_table"
local tsv_fields        = read_config("tsv_fields")
local encoder_module    = read_config("encoder_module")
local encode
if encoder_module then
    encode = require(encoder_module).encode
    if not encode then
        error(encoder_module .. " does not provide an encode function")
    end
end

local filename = string.format("%s/%s", batch_dir, read_config("Logger"))
local bq_cmd
local retry_at


local function load_data()
    return read_message(read_config("json_field") or "Payload")
end


if tsv_fields and type(tsv_fields) == "table" then
    filename = filename .. ".tsv"
    bq_cmd = string.format('bq load --source_format CSV -F "\t" --quote "" --ignore_unknown_values %s.%s %s', bq_dataset, bq_table, filename)
    load_data = function()
        local t = {}
        for i,f in ipairs(tsv_fields) do
            local v = read_message(f) or ""
            if f == "Timestamp" then
                v = os.date("%Y-%m-%d %H:%M:%S", v / 1e9)
            else
                v = string.gsub(tostring(v), "[\t\n]", " ")
            end
            t[i] = v
        end
        return table.concat(t, "\t")
    end
else
    filename = filename .. ".json"
    bq_cmd = string.format("bq load --source_format NEWLINE_DELIMITED_JSON --ignore_unknown_values %s.%s %s", bq_dataset, bq_table, filename)
end

if load_timeout then
    bq_cmd = string.format("timeout -s 9 %d %s", load_timeout, bq_cmd);
end

local fh = assert(io.open(filename, "a")) -- append to the current batch
fh:setvbuf("line")
local bytes_written = fh:seek()
local last_write = os.time()
local failed_cnt = 0

local alert_tmpl = [[
The bq load command has failed with return value: %d
The file has been temporarily saved off for manual inspection/correction.
Generally this is just an intermittent failure but if it is caused by an invalid schema
or corrupt file (see the project's job history) there is no reason to retry until it is
manually corrected.  Once corrected the file should be loaded using the following command.

%s.%d

The file can be deleted after a successful load.
]]
local function bq_load(is_timer_event)
    if retry_at and os.time() < retry_at then return end

    local mode = "w"
    fh:close()
    if bytes_written > 0 then
        local rv = os.execute(bq_cmd)
        if rv ~= 0 then
            if not retry_at then
                retry_at = os.time() + 60
                mode = "a"
            else
                failed_cnt = failed_cnt + 1
                local fn = filename .. "." .. tostring(failed_cnt)
                os.rename(filename, fn)
                if failed_cnt == load_fail_cache then
                    failed_cnt = 0
                end
                alert.send(read_config("Logger"), "bq load", string.format(alert_tmpl, rv / 256, bq_cmd, failed_cnt))
            end
        end
    end
    if mode == "w" then
        retry_at = nil
        bytes_written = 0
        last_write = os.time()
    end
    fh = io.open(filename, mode)
    fh:setvbuf("line")
end


function process_message()
    local ok, data
    if encode then
        ok, data = pcall(encode)
        if not ok then return -1, data end
        if not data then return -2 end
    else
        data = load_data()
    end
    fh:write(data, "\n")
    bytes_written = bytes_written + #data + 1
    if bytes_written >= max_file_size then
        bq_load()
    end
    return 0
end


function timer_event(ns, shutdown)
    if shutdown or ns/1e9 - last_write >= max_file_age then
        bq_load()
    end
end

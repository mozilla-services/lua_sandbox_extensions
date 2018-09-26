-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# GCP Logging Output

Maps the Heka protobuf message to a LogEntry and then delivers it to Stackdriver.

## Sample Configuration
```lua
filename            = "gcp_logging.lua"
message_matcher     = "Logger == 'input.nginx_access'"
ticker_interval     = 1 -- this should be zero when batch_size == 1 and max_async_requests == 0

channel             = "logging.googleapis.com"
project             = "projects/mozilla-data-poc-198117"
log_id_default      = "default"
-- log_id_field        = "Type" -- optional field to extract the log_id from, if nil the default is used
max_async_requests  = 20 -- default (0 synchronous only)
batch_size          = 1000 -- default/maximum
async_buffer_size   = max_async_requests * batch_size

-- explicit mapping; Heka message to LogEntry
log_entry_map       = {
    -- logName =        -- if not specified it is constructed from the project and log_id configuration
    -- resource = {}    -- if not specified it defaults to the gce_instance metadata
    timestamp   = "Timestamp",
    severity    = "Severity",
    insertId    = "Uuid",
    labels      = {
        Hostname        = "Hostname",
        bodyBytesSent   = "Fields[body_bytes_sent]",
        request         = "Fields[request]",
        remoteUser      = "Fields[remote_user]",
        type            = "nginx", -- treated as a literal
    },
    httpRequest = {
        remoteIp        = "Fields[remote_addr]",
        userAgent       = "Fields[http_user_agent]",
        status          = "Fields[status]",
        referer         = "Fields[referer]",
    },
    textPayload = read_message("Payload")
}
```
--]]

require "gcp.logging"
require "string"
require "table"

local es = require "lpeg.escape_sequences"

local channel               = read_config("channel") or "logging.googleapis.com"
local project               = read_config("project") or error"project must be set"
local log_id_default        = read_config("log_id_default") or error"log_id_default must be set"
local log_id_field          = read_config("log_id_field")
local log_entry_map         = read_config("log_entry_map")
assert(type(log_entry_map) == "table", "log_entry_map must be a table")
local batch_size = read_config("batch_size") or 1000
assert(batch_size > 0 and batch_size <= 1000)

local max_async_requests = read_config("max_async_requests") or 20
assert(max_async_requests >= 0)

local log_entry = {}
-- verify/populate the log_entry_map/log_entry
do
    local log_name_default = string.format("%s/logs/%s", project, es.escape_url(log_id_default))
    local function get_log_name()
        if not log_id_field then return log_name_default end
        local n = read_message(log_id_field)
        if n then return string.format("%s/logs/%s", project, es.escape_url(n)) end
        return log_name_default
    end

    local lookup = {Timestamp = true, Logger = true, Type = true,
        Hostname = true, Payload = true, Severity = true,
        EnvVersion = true, Pid = true}

    local function verify(map, entry)
        for k,v in pairs(map) do
            local t = type(v)
            if t == "string" then
                if lookup[v] or v:match("^Fields%[[^%]]*%]$") then
                    map[k] = function() return read_message(v) end
                elseif v == "Uuid" then
                    map[k] = function()
                        return string.format("%X%X%X%X-%X%X-%X%X-%X%X-%X%X%X%X%X%X",
                                             string.byte(read_message(v), 1, 16))
                    end
                end
            else
                local e = {}
                entry[k] = e
                verify(v, e)
            end

        end
    end
    verify(log_entry_map, log_entry)

    if not log_entry_map.logName then
        log_entry_map.logName = get_log_name
    end

    if not log_entry_map.resource then
        local http = require "socket.http"
        local ltn12 = require("ltn12")
        local function get_metadata(uri)
            local response = {}
            local request = {
                url = "http://metadata.google.internal/computeMetadata/v1/instance/" .. uri,
                sink = ltn12.sink.table(response),
                headers = {["Metadata-Flavor"] = "Google"}
                }
            local r, c, h = http.request(request)
            assert(r and c == 200, c)
            return table.concat(response)
        end

        local resource = {
            type = "gce_instance",
            labels = {
                instance_id = get_metadata("id"),
                zone        = get_metadata("zone"):match("zones/(.*)")
            }
        }
        log_entry_map.resource = function() return resource end
    end
end


local function populate_log_entry(map, entry)
    for k,v in pairs(map) do
        local t = type(v)
        if t == "function" then
            entry[k] = v()
        elseif t == "table" then
            populate_log_entry(v, entry[k])
        else
            entry[k] = v
        end
    end
end


local writer = gcp.logging.writer(channel, max_async_requests, batch_size)
local timer = true
if max_async_requests > 0 then
    local sid
    function process_message(sequence_id)
        writer:poll()
        sid = sequence_id

        populate_log_entry(log_entry_map, log_entry)

        local ok, status_code, err = pcall(writer.send, writer, sequence_id, log_entry)
        if not ok then return -1, status_code end
        if status_code == 0 then -- batch complete, flushed to network
            status_code = -5
            timer = false
        end
        return status_code, err
    end

    function timer_event(ns, shutdown)
        writer:poll()
        if timer or shutdown then
            pcall(writer.flush, writer, sid)
        end
        timer = true
    end
else
    function process_message()
        populate_log_entry(log_entry_map, log_entry)
        local ok, status_code, err = pcall(writer.send_sync, writer, log_entry)
        if not ok then return -1, status_code end
        if status_code == 0 then timer = false end
        return status_code, err
    end

    function timer_event(ns, shutdown)
        if timer or shutdown then
            local ok, err = pcall(writer.flush, write)
            if ok then update_checkpoint() end
        end
        timer = true
    end
end

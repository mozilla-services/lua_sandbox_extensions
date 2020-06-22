-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Papertrail Log Ingestion Delayed read to hopefully avoid missing data

Input plugin to read log events from the Papertrail API.  When reading data
from papertrail in real time even with tail=false data can still be skipped
and the checkpoint will happily advanced. Since there is no SLA on the data
availability or consistency and the papertrail support has not been helpful on
any issue basically stating whatever behavior you see is the expected behavior
even if it doesn't match the documentation. Between now and the time we drop
their service this delayed read should be a good enough fix.

For more information on the API see https://help.papertrailapp.com/kb/how-it-works/search-api/.

## Sample Configuration
```lua
filename = "papertrail_delay.lua"

ticker_interval = 60 -- required, polling interval

_key = "APIkey" -- required, papertrail API key

-- endpoint     = "https://papertrailapp.com/api/v1/events/search.json" -- default
-- limit        = 1000 -- default, max messages per interval
-- delay_read   = 300 -- default, number of seconds to delay
-- query        = nil -- optional, search query; return events matching this query (default: return all events)
-- system_id    = nil -- optional, limit results to a specific system (accepts ID or name)
-- group_id     = nil -- optional, limit results to a specific group (accepts ID only)
-- timeout      = 10  -- optional

-- decoder_module = "decoders.payload" -- default
```
--]]
require "os"
require "table"
require "string"

local lsys   = require("lpeg.syslog")
local http   = require("socket.http")
local https  = require("ssl.https")
local snk    = require("ltn12").sink.table
local jdec   = require("cjson").decode
local urlesc = require("socket.url").escape

local sdu    = require "lpeg.sub_decoder_util"
local decode = sdu.load_sub_decoder(read_config("decoder_module") or
                                    "decoders.payload", read_config("printf_messages"))

local endpoint          = read_config("endpoint") or "https://papertrailapp.com/api/v1/events/search.json"
local limit             = read_config("limit") or 1000
local delay_read        = read_config("delay_read") or 300
local interval          = read_config("ticker_interval")
local query             = read_config("query")
local rkey              = read_config("_key") or error("_key must be configured")
local default_headers   = read_config("default_headers") or {}
local system_id         = read_config("system_id")
if system_id then system_id = "&system_id=" .. system_id else system_id = "" end
local group_id          = read_config("group_id")
if group_id then group_id = "&group_id=" .. group_id else group_id = "" end
http.TIMEOUT            = read_config("timeout") or 10

assert(interval >= 60, "ticker_interval must be >= 60")

if query then query = "&q=" .. urlesc(query) else query = "" end

local err_msg = {
    Type    = "error.decode",
    Payload = nil,
    Fields  = {
        data = nil
    }
}

local headers = {
    ["X-Papertrail-Token"] = rkey
}

local function request_logs(min_time, max_time, id)
    local t = {}

    local param
    if id then
        param = string.format("?limit=%d%s%s%s&min_time=%d&max_id=%s", limit, system_id, group_id, query, min_time, id)
    else
        param = string.format("?limit=%d%s%s%s&min_time=%d&max_time=%d", limit, system_id, group_id, query, min_time, max_time)
    end

    local r, c = https.request({
        url     = endpoint .. param,
        headers = headers,
        sink    = snk(t)
    })

    if c ~= 200 then return -1, string.format("HTTP status code %s", tostring(c)) end

    local ok, j = pcall(jdec, table.concat(t))
    if not ok then return -1, j end
    return 0, nil, j
end


function process_message(checkpoint)
    local max_time = os.time() - delay_read
    local cp_time, cp_id
    if checkpoint then
        local a,b = checkpoint:match("(%d+)\t(%d+)")
        cp_time = tonumber(a)
        cp_id   = b
    else
        cp_time = max_time - 60
        cp_id = ""
    end

    local rv, err, j, id
    local pre_id = cp_id
    repeat
        if j then id = j.min_id end
        rv, err, j = request_logs(cp_time, max_time, id)
        if err then return rv, err end

        if j.max_id > cp_id then cp_id = j.max_id end
        for i,v in ipairs(j.events) do
            if v.id ~= id and v.id > pre_id then  -- on continuation reads discard the duplicated min_id
                                                  -- only keep the events that were newer than the previous checkpoint
                local msg = sdu.copy_message(default_headers, false)
                local data = v.message
                v.message = nil
                sdu.add_fields(msg, v)
                local ok, err = pcall(decode, data, msg, true)
                if not ok or err then
                    err_msg.Payload = err
                    err_msg.Fields.data = m
                    pcall(inject_message, err_msg)
                end
            end
        end
    until not j.reached_record_limit or not j.reached_time_limit or rv ~= 0

    inject_message(nil, string.format("%d\t%s", max_time, cp_id))

    return rv, err
end

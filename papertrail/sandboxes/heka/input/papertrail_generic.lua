-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Papertrail Log Ingestion

Input plugin to read log events from the Papertrail API.

For more information on the API see https://help.papertrailapp.com/kb/how-it-works/search-api/.

## Sample Configuration
```lua
filename = "papertrail.lua"

ticker_interval = 60 -- required, polling interval

_key = "APIkey" -- required, papertrail API key

-- endpoint     = "https://papertrailapp.com/api/v1/events/search.json" -- default
-- limit        = 1000 -- default, max messages per interval
-- query        = nil -- optional, search query; return events matching this query (default: return all events)
-- system_id    = nil -- optional, limit results to a specific system (accepts ID or name)
-- group_id     = nil -- optional, limit results to a specific group (accepts ID only)

-- decoder_module = "decoders.payload" -- default
```
--]]
require "table"
require "string"

local lsys   = require("lpeg.syslog")
local https  = require("ssl.https")
local snk    = require("ltn12").sink.table
local jdec   = require("cjson").decode
local urlesc = require("socket").url.escape

local sdu    = require "lpeg.sub_decoder_util"
local decode = sdu.load_sub_decoder(read_config("decoder_module") or
                                    "decoders.payload", read_config("printf_messages"))

local endpoint          = read_config("endpoint") or "https://papertrailapp.com/api/v1/events/search.json"
local limit             = read_config("limit") or 1000
local interval          = read_config("ticker_interval")
local query             = read_config("query")
local rkey              = read_config("_key") or error("_key must be configured")
local default_headers   = read_config("default_headers") or {}
local system_id         = read_config("system_id")
if system_id then system_id = "&system_id=" .. system_id else system_id = "" end
local group_id          = read_config("group_id")
if group_id then group_id = "&group_id=" .. group_id else group_id = "" end

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

local function request_logs(checkpoint)
    local t = {}

    local param = string.format("?limit=%d%s%s%s", limit, system_id, group_id, query)
    if checkpoint then
        param = string.format("%s&tail=false&min_id=%s", param, checkpoint)
    else
        param = string.format("%s&tail=false", param)
    end

    local r, c = https.request({
        url     = endpoint .. param,
        headers = headers,
        sink    = snk(t)
    })

    if c ~= 200 then return -1, string.format("HTTP status code %d", c) end

    local ok, j = pcall(jdec, table.concat(t))
    if not ok then return -1, j end
    return 0, nil, j
end


function process_message(checkpoint)
    local rv, err, j
    repeat
        rv, err, j = request_logs(checkpoint)
        if err then return rv, err end

        for i,v in ipairs(j.events) do
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
        checkpoint = j.max_id
        inject_message(nil, checkpoint)
    until not j.reached_record_limit or rv ~= 0

    return rv, err
end

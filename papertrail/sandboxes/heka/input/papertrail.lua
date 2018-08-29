-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Papertrail Log Ingestion

Input plugin to read log events from the Papertrail API. Messages read by this input plugin
and transformed into the original syslog message such that they can be fed through a syslog
decoder.

For more information on the API see https://help.papertrailapp.com/kb/how-it-works/search-api/.

## Sample Configuration
```lua
filename = "papertrail.lua"

ticker_interval = 60 -- required, polling interval

_key = "APIkey" -- required, papertrail API key

-- endpoint = "https://paper.trail.api" -- optional, override standard papertrail URL endpoint
-- limit = 1000 -- optional, max messages per interval, defaults to 1000
-- query = "ssh OR codesign" -- optional, filter incoming messages using papertrail query syntax

decoder_module = "decoders.syslog"

decoders_syslog = {
    template = "<%PRI%>%TIMESTAMP% %HOSTNAME% %syslogtag:1:32%%msg:::sp-if-no-1st-sp%%msg%"
    ...
}
```
--]]

require "table"
require "string"

local lsys   = require("lpeg.syslog")
local https  = require("ssl.https")
local ostime = require("os").time
local snk    = require("ltn12").sink.table
local jdec   = require("cjson").decode
local urlesc = require("socket").url.escape

local sdu       = require "lpeg.sub_decoder_util"
local decode    = sdu.load_sub_decoder(read_config("decoder_module") or
                      "decoders.heka.protobuf", read_config("printf_messages"))

local endpoint          = read_config("endpoint") or "https://papertrailapp.com/api/v1/events/search.json"
local limit             = read_config("limit") or 1000
local interval          = read_config("ticker_interval")
local query             = read_config("query")
local rkey              = read_config("_key") or error("_key must be configured")
local default_headers   = read_config("default_headers") or {}

assert(interval >= 60, "ticker_interval must be >= 60")

if query then query = urlesc(query) end

local err_msg = {
    Type    = "error.decode",
    Payload = nil,
    Fields  = {
        data = nil
    }
}

local wstart    = ostime() - (interval * 2)
local wend      = wstart + interval
local eidcache  = {}

local headers = {
    ["X-Papertrail-Token"] = rkey
}

local function request_logs()
    local t = {}

    local param = string.format("?min_time=%d&max_time=%d&limit=%d", wstart, wend, limit)
    if query then param = string.format("%s&q=%s", param, query) end
    local r, c = https.request({
        url     = endpoint .. param,
        headers = headers,
        sink    = snk(t)
    })
    if c ~= 200 then return nil, string.format("api request returned status code %d", c) end

    local ok, ret = pcall(jdec, table.concat(t))
    if not ok then return nil, ret end

    if not ret.events then return nil, "response did not contain events element" end
    return ret.events
end

local function composite(v)
    local pri = 30 -- 3 * 8 + 6, default to daemon.info
    if v.severity and v.facility then
        local sev = lsys.severity:match(string.lower(v.severity))
        local fac = lsys.facility:match(string.lower(v.facility))
        if sev and fac then pri = fac * 8 + sev end
    end
    return string.format("<%d>%s %s %s: %s", pri, v.display_received_at, v.hostname, v.program, v.message)
end

function process_message()
    local ev, err = request_logs()
    if err then return -1, err end

    local ncache = {}
    for i,v in ipairs(ev) do
        if not eidcache[v.id] then -- handle duplicate events on a window boundary
            ncache[v.id] = true
            local m = composite(v)
            local ok, err = pcall(decode, m, default_headers)
            if not ok then
                err_msg.Payload = err
                err_msg.Fields.data = m
                pcall(inject_message, err_msg)
            end
        end
    end
    eidcache = ncache

    wstart = wend
    wend   = ostime() - interval

    if #ev == limit then
        return -1, "configured input limit reached in interval"
    end
    return 0
end

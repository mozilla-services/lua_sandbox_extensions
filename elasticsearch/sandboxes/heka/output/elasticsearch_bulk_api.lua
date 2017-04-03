-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Elasticsearch Bulk API Output

## Sample Configuration
```lua
filename        = "elasticsearch_bulk_api.lua"
message_matcher = "Type == 'nginx'"
ticker_interval = 10 -- flush every 10 seconds or flush_count (50000) messages
memory_limit    = 200e6

address             = "127.0.0.1"
port                = 9200
timeout             = 10
flush_count         = 50000
flush_on_shutdown   = false
-- preserve_data       = false -- we don't rely on preserve data anymore
max_retry           = 0
discard_on_error    = false -- discard the batch after max_retry+1 failed attemps to send the batch
abort_on_error      = false -- stop this plugin after max_retry+1 failed attemps to send the batch
-- when setting abort_on_error=true, consider also settings shutdown_on_terminate or remove_checkpoints_on_terminate


-- See the elasticsearch module directory for the various encoders and configuration documentation.
encoder_module  = "encoders.elasticsearch.payload"
encoders_elasticsearch_common    = {
    es_index_from_timestamp = true,
    index                   = "%{Logger}-%{%Y.%m.%d}",
    type_name               = "%{Type}-%{Hostname}",
}
```
--]]

require "table"
require "rjson"
require "string"
local ltn12     = require "ltn12"
local time      = require "os".time
local socket    = require "socket"
local http      = require("socket.http")
local address   = read_config("address") or "127.0.0.1"
local port      = read_config("port") or 9200
local timeout   = read_config("timeout") or 10
local discard   = read_config("discard_on_error")
local abort     = read_config("abort_on_error")
local maxretry  = read_config("max_retry") or 0

local encoder_module = read_config("encoder_module") or "encoders.elasticsearch.payload"
local encode = require(encoder_module).encode
if not encode then
    error(encoder_module .. " does not provide an encode function")
end

local batch_file        = string.format("%s/%s.batch", read_config("output_path"), read_config("Logger"))
local flush_on_shutdown = read_config("flush_on_shutdown")
local ticker_interval   = read_config("ticker_interval")
local flush_count       = read_config("flush_count") or 50000
local last_flush        = time()

local client
local function create_client()
    local client = http.open(address, port)
    client.c:setoption("tcp-nodelay", true)
    client.c:setoption("keepalive", true)
    client.c:settimeout(timeout)
    return client
end
local pcreate_client = socket.protect(create_client);


local req_headers = {
    ["user-agent"]      = http.USERAGENT,
    ["content-type"]    = "application/x-ndjson",
    ["content-length"]  = 0,
    ["host"]            = address .. ":" .. port,
    ["accept"]          = "application/json",
    ["connection"]      = "keep-alive",
}

local function send_request() -- hand coded since socket.http doesn't support keep-alive connections
    local fh = assert(io.open(batch_file, "r"))
    req_headers["content-length"] = fh:seek("end")
    client:sendrequestline("POST", "/_bulk")
    client:sendheaders(req_headers)
    fh:seek("set")
    client:sendbody(req_headers, ltn12.source.file(fh, "invalid file handle"))
    local code = client:receivestatusline()
    local headers
    while code == 100 do -- ignore any 100-continue messages
        headers = client:receiveheaders()
        code = client:receivestatusline()
    end
    headers = client:receiveheaders()
    local ok, err, ret = true, nil, 0
    if code ~= 204 and code ~= 304 and not (code >= 100 and code < 200) then
        if code == 200 and string.match(headers["content-type"], "^application/json") then
            local body = {}
            local sink = ltn12.sink.table(body)
            client:receivebody(headers, sink)
            local response = table.concat(body)
            local ok, doc = pcall(rjson.parse, response)
            if ok then
                if doc:value(doc:find("errors")) then
                    ret = -1
                    err = string.format("ElasticSearch server reported errors processing the submission")
                end
            else
                ret = -3
                err = string.format("HTTP response didn't contain valid JSON. err: %s", doc)
            end
        else
            client:receivebody(headers, ltn12.sink.null())
        end

        if not err and code > 304 then
            ret = -1
            err = string.format("HTTP response error. Status: %d", code)
        end
    end

    if headers.connection == "close" then
        client:close()
        client = nil
    end

    return true, err, ret
end
local psend_request = socket.protect(function(client) return send_request(client) end)


local batch = assert(io.open(batch_file, "a+"))
local function send_batch()
    local err
    if not client then
        client, err = pcreate_client()
    end
    if err then return -3, err end -- retry indefinitely

    batch:flush()
    local ok, err, ret = psend_request(client)
    if not ok then -- network error
        client = nil
        return -3, err
    end
    last_flush = time()
    return ret, err
end

local batch_count = 0
local retry       = false
local try_count   = 0

for _ in io.lines(batch_file) do
    batch_count = batch_count + 1
end
batch_count = batch_count / 2
if batch_count >= flush_count then
    retry = true
end

local function send_batch2()
    try_count = try_count + 1
    local ret, err = send_batch()
    if ret < 0 then client = nil end -- always use a new connection after an error

    if ret == 0 then
        retry = false
    elseif discard and try_count > maxretry then
        retry = false
        err = string.format("Discarding %d messages after %d attemps, ret=%d err=%s", batch_count, try_count, ret, err)
        ret = -1
    elseif abort and try_count > maxretry then
        error(string.format("Abort sending %d messages after %d attemps, ret=%d err=%s", batch_count, try_count, ret, err))
    else
        retry = true
        err = string.format("Error sending %d messages, attemps nb %d, ret=%d err=%s", batch_count, try_count, ret, err)
        ret = -3
    end

    if not retry then
        batch_count = 0
        try_count   = 0
        batch:close()
        batch = assert(io.open(batch_file, "w"))
    end

    return ret, err
end

function process_message()
    if not retry then
        local ok, data = pcall(encode)
        if not ok then return -1, data end
        if not data then return -2 end
        batch:write(data)
        batch_count = batch_count + 1
    end

    if batch_count >= flush_count then
        return send_batch2()
    end
    return 0
end


function timer_event(ns, shutdown)
    local timedout = (ns / 1e9 - last_flush) >= ticker_interval
    if (timedout or (shutdown and flush_on_shutdown)) and batch_count > 0 then
        send_batch2()
    end
end

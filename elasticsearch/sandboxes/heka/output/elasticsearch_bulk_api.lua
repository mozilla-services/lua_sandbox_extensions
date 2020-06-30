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
-- TLS support; only set if you want TLS
ssl_params = {
  protocol = "tlsv1_2",
  cafile = "/etc/ssl/certs/ca-certificates.crt",
  verify = {"peer", "fail_if_no_peer_cert"},
  options = {"all", "no_sslv3"}
}
port                = 9200
-- set basic auth parameters to enable basic authentication
basic_auth_params   = { username = "Aladdin", _password = "open sesame" }
timeout             = 10    -- socket timeout
flush_count         = 50000
flush_on_shutdown   = false
preserve_data       = false -- there is no state maintained in this plugin
max_retry           = 0     -- number of seconds (retries once per second)
discard_on_error    = false -- discard the batch after max_retry + 1 failed attempts to send the batch
abort_on_error      = false -- stop this plugin after max_retry + 1 failed attempts to send the batch
-- when setting abort_on_error = true, consider also settings shutdown_on_terminate or remove_checkpoints_on_terminate
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
local ltn12             = require "ltn12"
local time              = require "os".time
local socket            = require "socket"
local http              = require("socket.http")
local mime              = require "mime"
local address           = read_config("address") or "127.0.0.1"
local port              = read_config("port") or 9200
local basic_auth_params = read_config("basic_auth_params")
local timeout           = read_config("timeout") or 10
local discard           = read_config("discard_on_error")
local abort             = read_config("abort_on_error")
local max_retry         = read_config("max_retry") or 0
local ssl_params        = read_config("ssl_params")
assert(not (abort and discard), "abort_on_error and discard_on_error are mutually exclusive")

local encoder_module = read_config("encoder_module") or "encoders.elasticsearch.payload"
local encode = require(encoder_module).encode
if not encode then
    error(encoder_module .. " does not provide an encode function")
end

local batch_file        = string.format("%s/%s.batch", read_config("output_path"), read_config("Logger"))
local flush_on_shutdown = read_config("flush_on_shutdown")
local ticker_interval   = read_config("ticker_interval")
local flush_count       = read_config("flush_count") or 50000
assert(flush_count > 0, "flush_count must be greater than zero")

local ssl, ssl_ctx
if ssl_params then
    ssl = require "ssl"
    -- Force client mode
    ssl_params.mode = "client"
    ssl_ctx = assert(ssl.newcontext(ssl_params))
end

local function connection_factory()
    local t = {c = socket.try(socket.tcp())}

    function idx (tbl, key)
        return function (prxy, ...)
            local c = prxy.c
            return c[key](c,...)
        end
    end

    function t:connect(host, port)
        socket.try(self.c:connect(host, port))
        self.c:setoption("tcp-nodelay", true)
        self.c:setoption("keepalive", true)
        self.c:settimeout(timeout)
        if ssl_params then
            self.c = socket.try(ssl.wrap(self.c, ssl_params))
            self.c:sni(host)
            socket.try(self.c:dohandshake())
        end
        return 1
    end

    return setmetatable(t, {__index = idx})
end

local client
local function create_client()
    return http.open(address, port, connection_factory)
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

local function basic_auth_string(params)
    return "Basic " .. mime.b64(params.username .. ":" .. params._password)
end

if basic_auth_params then
    req_headers["authorization"] = basic_auth_string(basic_auth_params)
end

local batch_count   = 0

local function send_request() -- hand coded since socket.http doesn't support keep-alive connections
    if not client then client, err = pcreate_client() end
    if err then print(err); return false; end

    local success = true
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
    if code ~= 204 and code ~= 304 and not (code >= 100 and code < 200) then
        if code == 200 and string.match(headers["content-type"], "^application/json") then
            local body = {}
            local sink = ltn12.sink.table(body)
            client:receivebody(headers, sink)
            local response = table.concat(body)
            local ok, doc = pcall(rjson.parse, response)
            if ok then
                if doc:value(doc:find("errors")) then
                    local retriable_error_count = 0
                    local total_error_count = 0
                    local items = doc:find("items")
                    for _,i in doc:iter(items) do
                        for _,a in doc:iter(i) do
                            local status = doc:value(doc:find(a, "status")) or 0
                            -- only consider 403 as retriable for now
                            if status == 403 then
                                retriable_error_count = retriable_error_count + 1
                            end
                            if status >= 400 then
                                total_error_count = total_error_count + 1
                            end
                        end
                    end

                    if retriable_error_count >= batch_count then
                        success = false
                        print(string.format("ElasticSearch rejected all %d messages, batch will be retried (check your cluster)", retriable_error_count))
                    else
                        print(string.format("ElasticSearch server reported errors processing the submission, not all messages were indexed (err: %d, tot: %d)", total_error_count, batch_count))
                        -- todo track partial batch failure counts https://github.com/mozilla-services/lua_sandbox_extensions/issues/89
                        -- the partial failure is most likely due to bad input, so no retry is attempted as it would just fail again
                    end
                end
            else
                print(string.format("HTTP response didn't contain valid JSON. err: %s", doc))
            end
        else
            client:receivebody(headers, ltn12.sink.null())
        end

        if code > 304 then
            success = false
            print(string.format("HTTP response error. Status: %d", code))
        end
    end

    if headers.connection == "close" then
        client:close()
        client = nil
    end

    return success
end
local psend_request = socket.protect(function() return send_request() end)


local send_on_start = false
local last_flush    = time()
local retry_count   = 0
local batch = assert(io.open(batch_file, "a+"))
for _ in io.lines(batch_file) do  -- ensure we have a correct count when resuming after an abort
    batch_count = batch_count + 1
end
batch_count = batch_count / 2
if batch_count >= flush_count then
    send_on_start = true
end

local function finalize_batch()
    last_flush  = time()
    batch_count = 0
    retry_count = 0
    batch:close()
    batch = assert(io.open(batch_file, "w"))
end

local function send_batch()
    batch:flush()
    local ok, err = psend_request()
    if not ok then
        if err then print(err) end
        client = nil
        retry_count = retry_count + 1
        if discard and retry_count > max_retry then
            print(string.format("discarded %d messages", batch_count))
            finalize_batch()
            return true
        elseif abort and retry_count > max_retry then
            error(string.format("Abort sending %d messages after %d attempts", batch_count, retry_count))
        end
        return false
    end
    finalize_batch()
    return true
end


function process_message()
    if batch_count >= flush_count then -- attempt to transmit a failed batch before accepting new data
        if not send_batch() then
            return -3 -- retry until successful or it errors out
        end
        if not send_on_start then
            return 0 -- break the retry loop and allow new data to start flowing again
        end
        send_on_start = false
    end

    local ok, data = pcall(encode)
    if not ok then return -1, data end
    if not data then return -2 end
    batch:write(data)
    batch_count = batch_count + 1

    if batch_count >= flush_count then
        send_batch()
    end
    return 0
end


function timer_event(ns, shutdown)
    local timedout = (ns / 1e9 - last_flush) >= ticker_interval
    if (timedout or (shutdown and flush_on_shutdown)) and batch_count > 0 then
        send_batch()
    end
end

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# GCP Pub/Sub Subscriber Input

## Sample Configuration
```lua
filename            = "gcp_pubsub.lua"
ticker_interval     = 1

channel             = "pubsub.googleapis.com"
project             = "projects/mozilla-data-poc-198117"
topic               = "pubsub_grpc"
subscription_name   = "test"
batch_size          = 1000 -- default/maximum
max_async_requests  = 20 -- default (0 synchronous only)

-- Heka message table containing the default header values to use, if they are
-- not populated by the decoder. If 'Fields' is specified it should be in the
-- hashed based format see:  http://mozilla-services.github.io/lua_sandbox/heka/message.html
-- This input will always default the Type header to the specified streamName.
-- default_headers = nil

-- printf_messages = -- see: https://mozilla-services.github.io/lua_sandbox_extensions/lpeg/modules/lpeg/printf.html

-- Specifies a module that will decode the raw data and inject the resulting message.
-- Supports the same syntax as an individual sub decoder
-- see: https://mozilla-services.github.io/lua_sandbox_extensions/lpeg/io_modules/lpeg/sub_decoder_util.html
-- Default:
-- decoder_module = "decoders.heka.protobuf"
```
--]]

require "gcp.pubsub"
require "string"

local sdu       = require "lpeg.sub_decoder_util"
local decode    = sdu.load_sub_decoder(read_config("decoder_module") or "decoders.heka.protobuf", read_config("printf_messages"))

local channel   = read_config("channel") or "pubsub.googleapis.com"
local project   = read_config("project") or error"project must be set"

local topic     = read_config("topic") or error"topic must be set"
topic = string.format("%s/topics/%s", project, topic)

local subscription_name = read_config("subscription_name") or string.format("%s_%s", read_config("Hostname"), read_config("Logger"))
subscription_name = string.format("%s/subscriptions/%s", project, subscription_name)

local batch_size = read_config("batch_size") or 1000
assert(batch_size > 0 and batch_size <= 1000)

local max_async_requests = read_config("max_async_requests") or 20

local default_headers = read_config("default_headers") or {}
assert(type(default_headers) == "table", "invalid default_headers type")
default_headers.Type = topic

local err_msg = {
    Type    = "error.decode",
    Payload = nil,
    Fields  = {
        data = nil
    }
}

local subscriber = gcp.pubsub.subscriber(channel, topic, subscription_name, max_async_requests)
local is_running = is_running
if max_async_requests > 0 then
    function process_message()
        while is_running() do
            local ok, msgs, cnt = pcall(subscriber.pull, subscriber, batch_size)
            if not ok then return -1, msgs end

            if cnt > 0 then
                for i=1, cnt do
                    local ok, err = pcall(decode, msgs[i], default_headers)
                    if not ok or err then
                        err_msg.Payload = err
                        err_msg.Fields.data = data
                        pcall(inject_message, err_msg)
                    end
                end
            end
        end
        return 0
    end
else
    function process_message()
        while is_running() do
            local ok, msgs, cnt = pcall(subscriber.pull_sync, subscriber, batch_size)
            if not ok then return -1, msgs end

            if cnt > 0 then
                for i=1, cnt do
                    local ok, err = pcall(decode, msgs[i], default_headers)
                    if not ok or err then
                        err_msg.Payload = err
                        err_msg.Fields.data = data
                        pcall(inject_message, err_msg)
                    end
                end
            else
                break -- poll every ticker_interval
            end
        end
        return 0
    end
end

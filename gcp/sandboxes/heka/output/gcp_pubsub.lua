-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# GCP Pub/Sub Output

## Sample Configuration
```lua
filename            = "gcp_pubsub.lua"
message_matcher     = "TRUE"
ticker_interval     = 1 -- this should be zero when batch_size == 1 and max_async_requests == 0

channel             = "pubsub.googleapis.com"
project             = "projects/mozilla-data-poc-198117"
topic               = "pubsub_grpc"
batch_size          = 1000 -- default/maximum
max_async_requests  = 20 -- default (0 synchronous only)
async_buffer_size   = max_async_requests * batch_size

-- Specify a module that will encode/convert the Heka message into its output representation.
encoder_module = "encoders.heka.protobuf" -- default
```
--]]

require "gcp.pubsub"
require "string"

local channel   = read_config("channel") or "pubsub.googleapis.com"
local project   = read_config("project") or error"project must be set"

local topic     = read_config("topic") or error"topic must be set"
topic = string.format("%s/topics/%s", project, topic)

local batch_size = read_config("batch_size") or 1000
assert(batch_size > 0 and batch_size <= 1000)

local max_async_requests = read_config("max_async_requests") or 20

local encoder_module = read_config("encoder_module") or "encoders.heka.protobuf"
local encode = require(encoder_module).encode
if not encode then
    error(encoder_module .. " does not provide an encode function")
end

local publisher = gcp.pubsub.publisher(channel, topic, max_async_requests)

if batch_size == 1 then
    if max_async_requests > 0 then
        function process_message(sequence_id)
            publisher:poll()
            local ok, data = pcall(encode)
            if not ok then return -1, data end
            if not data then return -2 end

            local ok, err = pcall(publisher.publish, publisher, sequence_id, data)
            if not ok then return -1, err end
            if err == 1 then
                return -3, "queue full"
            end
            return -5 -- asynchronous checkpoint management
        end

        function timer_event(ns)
            publisher:poll()
        end
    else
        function process_message()
            local ok, data = pcall(encode)
            if not ok then return -1, data end
            if not data then return -2 end

            local ok, err = pcall(publisher.publish_sync, publisher, data)
            if not ok then return -1, err end
            return 0
        end

        function timer_event()
        end
    end
else
    local batch_cnt = 0
    local batch = {}
    local timer = true

    if max_async_requests > 0 then
        local sid
        local function flush_batch(sequence_id)
            publisher:publish(sequence_id, batch)
            batch = {}
            batch_cnt = 0
            timer = false
        end

        function process_message(sequence_id)
            publisher:poll()
            sid = sequence_id
            local ok, data = pcall(encode)
            if not ok then return -1, data end
            if not data then return -2 end

            batch_cnt = batch_cnt + 1
            batch[batch_cnt] = tostring(data)
            if batch_cnt >= batch_size then
                local ok, err = pcall(flush_batch, sid)
                if not ok then
                    batch[batch_cnt] = nil
                    batch_cnt = batch_cnt - 1
                    return -3, err -- retry
                end
            end
            return -5 -- asynchronous checkpoint management
        end

        function timer_event(ns, shutdown)
            publisher:poll()
            if batch_cnt > 0 and (timer or shutdown) then
                pcall(flush_batch, sid)
            end
            timer = true
        end
    else
        local function flush_batch()
            publisher:publish_sync(batch)
            batch = {}
            batch_cnt = 0
            timer = false
        end

        function process_message()
            local ok, data = pcall(encode)
            if not ok then return -1, data end
            if not data then return -2 end

            batch_cnt = batch_cnt + 1
            batch[batch_cnt] = tostring(data)
            if batch_cnt >= batch_size then
                local ok, err = pcall(flush_batch)
                if not ok then
                    batch[batch_cnt] = nil
                    batch_cnt = batch_cnt - 1
                    return -3, err -- retry
                end
                return 0
            end
            return -4 -- batch
        end

        function timer_event(ns, shutdown)
            if batch_cnt > 0 and (timer or shutdown) then
                local ok, err = pcall(flush_batch)
                if ok then update_checkpoint() end
            end
            timer = true
        end
    end
end

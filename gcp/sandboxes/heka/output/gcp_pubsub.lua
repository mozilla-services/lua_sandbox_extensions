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
project             = "mozilla-data-poc-198117"
topic               = "pubsub_grpc"
batch_size          = 1000 -- default/maximum
max_async_requests  = 20 -- default (0 synchronous only)
async_buffer_size   = max_async_requests * batch_size

-- Specify a module that will encode/convert the Heka message into its output representation.
encoder_module = nil -- default uses msg.Payload as the data and converts the headers and non-binary fields to string attributes
```
--]]

require "gcp.pubsub"
require "string"

local channel   = read_config("channel") or "pubsub.googleapis.com"
local project   = read_config("project") or error"project must be set"
project         = project:match("^projects/.+") or "projects/" .. project
local topic     = read_config("topic") or error"topic must be set"
topic           = topic:match("^projects/.+") or string.format("%s/topics/%s", project, topic)

local batch_size = read_config("batch_size") or 1000
assert(batch_size > 0 and batch_size <= 1000)

local max_async_requests = read_config("max_async_requests") or 20
assert(max_async_requests >= 0)

local encoder_module = read_config("encoder_module")
local encode
if encoder_module then
    encode = require(encoder_module).encode
    if not encode then
        error(encoder_module .. " does not provide an encode function")
    end
end


local publisher = gcp.pubsub.publisher(channel, topic, max_async_requests, batch_size)
local timer = true
if max_async_requests > 0 then
    local sid
    function process_message(sequence_id)
        publisher:poll()
        sid = sequence_id
        local ok, data
        if encode then
            ok, data = pcall(encode)
            if not ok then return -1, data end
            if not data then return -2 end
        end

        local ok, status_code = pcall(publisher.publish, publisher, sequence_id, data)
        if not ok then return -1, status_code end
        if status_code == 0 then -- batch complete, flushed to network
            status_code = -5
            timer = false
        end
        return status_code
    end

    function timer_event(ns, shutdown)
        publisher:poll()
        if timer or shutdown then
            pcall(publisher.flush, publisher, sid)
        end
        timer = true
    end
else
    function process_message()
        local ok, data
        if encode then
            ok, data = pcall(encode)
            if not ok then return -1, data end
            if not data then return -2 end
        end

        local ok, status_code = pcall(publisher.publish_sync, publisher, data)
        if not ok then return -1, status_code end
        if status_code == 0 then timer = false end
        return status_code
    end

    function timer_event(ns, shutdown)
        if timer or shutdown then
            local ok, err = pcall(publisher.flush, publisher)
            if ok then update_checkpoint() end
        end
        timer = true
    end
end

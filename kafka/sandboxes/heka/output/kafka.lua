-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "kafka"

--[[
# Heka Kafka Producer Output

## Sample Configuration
```lua
filename               = "kafka.lua"
message_matcher        = "TRUE"
output_limit           = 8 * 1024 * 1024
brokerlist             = "localhost:9092" -- see https://github.com/edenhill/librdkafka/blob/master/src/rdkafka.h#L2205
ticker_interval        = 60
async_buffer_size      = 20000

topic_constant = "test"
producer_conf = {
    ["queue.buffering.max.messages"] = async_buffer_size,
    ["batch.num.messages"] = 200,
    ["message.max.bytes"] = output_limit,
    ["queue.buffering.max.ms"] = 10,
    ["topic.metadata.refresh.interval.ms"] = -1,
}

-- https://github.com/edenhill/librdkafka/blob/master/CONFIGURATION.md#topic-configuration-properties
topic_confs = {
    -- <topic_name> = {<topic_conf>},
    ["*"] = {<topic_conf>} -- optional default topic configuration
}

-- Specify a module that will encode/convert the Heka message into its output representation.
encoder_module = "encoders.heka.protobuf" -- default
```
--]]
local brokerlist        = read_config("brokerlist") or error("brokerlist must be set")
local topic_constant    = read_config("topic_constant")
local topic_variable    = read_config("topic_variable") or "Logger"
local producer_conf     = read_config("producer_conf")
local topic_confs       = read_config("topic_confs") or {}
local encoder_module    = read_config("encoder_module") or "encoders.heka.protobuf"
local encode = require(encoder_module).encode
if not encode then
    error(encoder_module .. " does not provide an encode function")
end

assert(type(topic_confs) == "table", "topic_confs must be a table")
for k,v in pairs(topic_confs) do
    assert(type(v) == "table", k .. " topic_conf must be a table")
    if k == "*" then
        local mt = {__index = function(t, k) return v end }
        setmetatable(topic_confs, mt);
    end
end

local producer = kafka.producer(brokerlist, producer_conf)

function process_message(sequence_id)
    local topic = topic_constant
    if not topic then
        topic = read_message(topic_variable) or "unknown"
    end
    producer:create_topic(topic, topic_confs[topic]) -- creates the topic if it does not exist

    producer:poll()
    local ok, data = pcall(encode)
    if not ok then return -1, data end
    if not data then return -2 end
    local ret = producer:send(topic, -1, sequence_id, data)

    if ret ~= 0 then
        if ret == 105 then
            return -3, "queue full" -- retry
        elseif ret == 90 then
            return -1, "message too large" -- fail
        elseif ret == 2 then
            error("unknown topic: " .. topic)
        elseif ret == 3 then
            error("unknown partition")
        end
    end

    return -5 -- asynchronous checkpoint management
end

function timer_event(ns)
    producer:poll()
end

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Kafka Consumer Input

## Sample Configuration
```lua
filename                = "kafka.lua"
output_limit            = 8 * 1024 * 1024
brokerlist              = "localhost:9092" -- see https://github.com/edenhill/librdkafka/blob/master/src/rdkafka.h#L2205

-- In balanced consumer group mode a consumer can only subscribe on topics, not topics:partitions.
-- The partition syntax is only used for manual assignments (without balanced consumer groups).
topics                  = {"test"}

-- https://github.com/edenhill/librdkafka/blob/master/CONFIGURATION.md#global-configuration-properties
consumer_conf = {
    ["group.id"] = "test_group", -- must always be provided (a single consumer is considered a group of one
    -- in that case make this a unique identifier)
    ["message.max.bytes"] = output_limit,
}

-- https://github.com/edenhill/librdkafka/blob/master/CONFIGURATION.md#topic-configuration-properties
topic_conf = {
    -- ["auto.commit.enable"] = true, -- cannot be overridden
    -- ["offset.store.method"] = "broker, -- cannot be overridden
}

-- Specify a module that will decode the raw data and inject the resulting message.
decoder_module = "decoders.heka.protobuf" -- default
```
--]]

require "kafka"

local brokerlist     = read_config("brokerlist") or error("brokerlist must be set")
local topics         = read_config("topics") or error("topics must be set")
local consumer_conf  = read_config("consumer_conf")
local topic_conf     = read_config("topic_conf")
local decoder_module = read_config("decoder_module") or "decoders.heka.protobuf"
local decode         = require(decoder_module).decode
if not decode then
    error(decoder_module .. " does not provide a decode function")
end

local is_running    = is_running
local consumer      = kafka.consumer(brokerlist, topics, consumer_conf, topic_conf)

local default_headers = {
    Type = nil,
}

local err_msg = {
    Logger  = read_config("Logger"),
    Type    = "error",
    Payload = nil,
}

function process_message()
    while is_running() do
        local data, topic, partition, key = consumer:receive()
        if data then
            default_headers.Type = topic
            local ok, err = pcall(decode, data, default_headers)
            if not ok or err then
                err_msg.Payload = err
                pcall(inject_message, err_msg)
            end
        end
    end
    return 0
end

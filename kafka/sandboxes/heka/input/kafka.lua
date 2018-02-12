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

-- Heka message table containing the default header values to use, if they are
-- not populated by the decoder. If 'Fields' is specified it should be in the
-- hashed based format see:  http://mozilla-services.github.io/lua_sandbox/heka/message.html
-- This input will always default the Type header to the Kafka topic name.
-- Default:
-- default_headers = nil

-- printf_messages = -- see: https://mozilla-services.github.io/lua_sandbox_extensions/lpeg/modules/lpeg/printf.html

-- Specifies a module that will decode the raw data and inject the resulting message.
-- Supports the same syntax as an individual sub decoder
-- see: https://mozilla-services.github.io/lua_sandbox_extensions/lpeg/io_modules/lpeg/sub_decoder_util.html
-- Default:
-- decoder_module = "decoders.heka.protobuf"
```
--]]

require "kafka"
local sdu       = require "lpeg.sub_decoder_util"
local decode    = sdu.load_sub_decoder(read_config("decoder_module") or "decoders.heka.protobuf", read_config("printf_messages"))

local brokerlist      = read_config("brokerlist") or error("brokerlist must be set")
local topics          = read_config("topics") or error("topics must be set")
local consumer_conf   = read_config("consumer_conf")
local topic_conf      = read_config("topic_conf")
local default_headers = read_config("default_headers") or {}
assert(type(default_headers) == "table", "invalid default_headers cfg")

local is_running    = is_running
local consumer      = kafka.consumer(brokerlist, topics, consumer_conf, topic_conf)

local err_msg = {
    Type    = "error.decode",
    Payload = nil,
    Fields  = {
        data = nil
    }
}

function process_message()
    while is_running() do
        local data, topic, partition, key = consumer:receive()
        if data then
            default_headers.Type = topic
            local ok, err = pcall(decode, data, default_headers)
            if not ok or err then
                err_msg.Payload = err
                err_msg.Fields.data = data
                pcall(inject_message, err_msg)
            end
        end
    end
    return 0
end

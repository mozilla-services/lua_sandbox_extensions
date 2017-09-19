-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Kinesis Single Record Producer Output

## Sample Configuration
```lua
filename            = "kinesis_single.lua"
message_matcher     = "TRUE"
ticker_interval     = 0

streamName          = "foobar"
-- partitionField      = "Uuid"
-- credeentialProvider = "INSTANCE"
-- clientConfig        = nil

-- Specify a module that will encode/convert the Heka message into its output representation.
encoder_module = "encoders.heka.protobuf" -- default
```
--]]

require "aws.kinesis"

local streamName            = read_config("streamName") or error"streamName must be set"
local partitionField        = read_config("partitionField") or "Uuid"
local credentialProvider    = read_config("credentialProvider") or "INSTANCE"
local clientConfig          = read_config("clientConfig") or {}
assert(type(clientConfig) == "table", "invalid clientConfig type")

local encoder_module = read_config("encoder_module") or "encoders.heka.protobuf"
local encode = require(encoder_module).encode
if not encode then
    error(encoder_module .. " does not provide an encode function")
end

local producer = aws.kinesis.simple_producer(clientConfig, credentialProvider)

function process_message()
    local ok, data = pcall(encode)
    if not ok then return -1, data end
    if not data then return -2 end

    local err = producer:send(streamName, data, read_message(partitionField))
    if err then return -1, err end
    return 0
end

function timer_event(ns)
end

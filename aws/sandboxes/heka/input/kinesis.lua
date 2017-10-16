-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# AWS Kinesis Consumer Input

## Sample Configuration
```lua
filename            = "kinesis.lua"
ticker_interval     = 5 -- recover from failure but allow it to be captured in the stats

streamName          = "foobar"
-- iteratorType        = "TRIM_HORIZON"
-- credentialProvider  = "INSTANCE"

-- table of AWS Client Configuration settings see:
-- https://sdk.amazonaws.com/cpp/api/LATEST/struct_aws_1_1_client_1_1_client_configuration.html
-- clientConfig        = nil

-- Heka message table containing the default header values to use, if they are
-- not populated by the decoder. If 'Fields' is specified it should be in the
-- hashed based format see:  http://mozilla-services.github.io/lua_sandbox/heka/message.html
-- This input will always default the Type header to the specified streamName.
-- default_headers = nil

-- Specify a module that will decode the raw data and inject the resulting message.
-- Default:
-- decoder_module = "decoders.heka.protobuf"
```
--]]

require "aws.kinesis"
require "string"
require "os"

local streamName    = read_config("streamName") or error"streamName must be set"
local iteratorType  = read_config("iteratorType") or "TRIM_HORIZON"
if iteratorType == "MIDNIGHT" then
    local t = os.time()
    iteratorType = t - t % 86400
end

local credentialProvider    = read_config("credentialProvider") or "INSTANCE"
local clientConfig          = read_config("clientConfig") or {}
assert(type(clientConfig) == "table", "invalid clientConfig type")

local default_headers = read_config("default_headers") or {}
assert(type(default_headers) == "table", "invalid default_headers type")
default_headers.Type = streamName

local decoder_module    = read_config("decoder_module") or "decoders.heka.protobuf"
local decode            = require(decoder_module).decode
if not decode then
    error(decoder_module .. " does not provide a decode function")
end

local err_msg = {
    Logger  = read_config("Logger"),
    Type    = "error",
    Payload = nil,
}

local is_running = is_running
function process_message(cp)
    local reader = aws.kinesis.simple_consumer(streamName, iteratorType, cp, clientConfig, credentialProvider)
    while is_running() do
        local ok, records, cp = pcall(reader.receive, reader)
        if not ok then return -1, records end

        for i, data in ipairs(records) do
            local ok, err = pcall(decode, data, default_headers)
            if not ok or err then
                err_msg.Payload = err
                pcall(inject_message, err_msg)
            end
            if cp then inject_message(nil, cp) end
        end
    end
    return 0
end

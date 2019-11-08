-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka AMQP Consumer Input

## Sample Configuration
```lua
filename                = "amqp.lua"
output_limit            = 8 * 1024 * 1024
ticker_interval         = 1 -- attempt to restablish a connection after a failure

amqp = {
    host                = "amqp.example.com",
    port                = 5672, -- default
    user                = "guest",
    _password           = "guest",
    connect_timeout     = 10, -- default seconds
    exchange            = "exchange/foo/bar",
    binding             = "#", -- default
    queue_name          = nil, -- creates an exclusive/temporary queue
    manual_ack          = false,
    passive             = false,
    durable             = false,
    exclusive           = false,
    auto_delete         = false,
    prefetch_size       = 0,
    prefetch_count      = 1, -- default, read one at a time
    ssl = { -- optional if not provided ssl is disabled use ssl = {} to enable with defaults
        _key            = nil,  -- path to client key
        cert            = nil,  -- path to client cert
        cacert          = nil,  -- path to credential authority cert
        verifypeer      = false,
        verifyhostname  = false
    }
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

require "amqp"
require "string"
local sdu       = require "lpeg.sub_decoder_util"
local decode    = sdu.load_sub_decoder(read_config("decoder_module") or "decoders.heka.protobuf", read_config("printf_messages"))

local amqp_cfg = read_config("amqp")
if type(amqp_cfg) ~= "table" then error("invalid amqp configuration") end
if not amqp_cfg.prefetch_count then amqp_cfg.prefetch_count = 1 end

local default_headers = read_config("default_headers") or {}
assert(type(default_headers) == "table", "invalid default_headers cfg")
if not default_headers.Fields then default_headers.Fields = {} end
default_headers.Fields.queue_name = amqp_cfg.queue_name

local is_running = is_running

local err_msg = {
    Type    = "error.decode",
    Payload = nil,
    Fields  = {
        data = nil,
        queue_name = amqp_cfg.queue_name
    }
}


function process_message()
    local ok, consumer = pcall(amqp.consumer, amqp_cfg)
    if not ok then
        if consumer:match("^configuration error") then
            error(consumer)
        end
        return -1, consumer
    end

    local cnt = 0
    while is_running() do
        local ok, data, content_type, exchange, routing_key = pcall(consumer.receive, consumer)
        if not ok then return -1, data end

        if data then
            cnt = cnt + 1
            default_headers.Fields.exchange     = exchange
            default_headers.Fields.content_type = content_type
            default_headers.Fields.routing_key  = routing_key
            local ok, err = pcall(decode, data, default_headers)
            if not ok or err then
                err_msg.Payload             = err
                err_msg.Fields.data         = data
                err_msg.Fields.exchange     = exchange
                err_msg.Fields.content_type = content_type
                err_msg.Fields.routing_key  = routing_key
                pcall(inject_message, err_msg)
            end
        end

        if cnt > 0 and (not data or cnt >= amqp_cfg.prefetch_count) then
            consumer:ack()
            cnt = 0
        end
    end
    return 0
end

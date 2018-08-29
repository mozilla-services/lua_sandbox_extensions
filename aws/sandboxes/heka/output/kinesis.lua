-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Kinesis Producer Output

## Sample Configuration
```lua
filename            = "kinesis_single.lua"
message_matcher     = "TRUE"
ticker_interval     = 0 -- set >0 to timeout/send any packed messages

streamName              = "foobar"
-- partitionField       = "Uuid"
-- credentialProvider   = "INSTANCE"
-- clientConfig         = nil
-- roleArn              = nil

-- Due to the way Kinesis is billed it makes senses to pack multiple items
-- into a single message to reduce the PUT Payload Unit charges. Packing by
-- partition can be done but not without the potential for some data loss under
-- error conditions (the feature was cut but a reference implementation is
-- available on request).
pack_percentage = 0 -- fill percentage of the put request (0 (no packing) - 100).
         -- The record won't be sent unless the current PUT Payload unit is this
         -- percentage full or the record has reached its maximum size or the
         -- timeout is triggered.
pack_delimiter = nil    -- Used to add a record delimiter, if necessary

-- Specify a module that will encode/convert the Heka message into its output representation.
encoder_module = "encoders.heka.framed_protobuf" -- default
```
--]]

require "aws.kinesis"
require "string"
require "table"
require "xxhash"

local PUT_MAX   = 1024 * 1024
local PUT_UNIT  = 25 * 1024

local streamName            = read_config("streamName") or error"streamName must be set"
local partitionField        = read_config("partitionField") or "Uuid"
local credentialProvider    = read_config("credentialProvider") or "INSTANCE"
local roleArn
if credentialProvider == "ROLE" then
    roleArn = read_config("roleArn") or error"roleArn must be set"
end
local clientConfig          = read_config("clientConfig") or {}
assert(type(clientConfig) == "table", "invalid clientConfig type")

local encoder_module = read_config("encoder_module") or "encoders.heka.framed_protobuf"
local encode = require(encoder_module).encode
if not encode then
    error(encoder_module .. " does not provide an encode function")
end

local pack_percentage = read_config("pack_percentage") or 0
assert(pack_percentage >= 0 and pack_percentage <= 100, "0 <= pack_percentage <= 100")
pack_percentage = pack_percentage / 100 * PUT_UNIT
local pack
if pack_percentage > 0 then
    pack = {
        cnt = 0,
        size = 0,
        timer = true,
        msgs = {},
        key = nil
        }
end

local pack_delimiter = read_config("pack_delimiter")
local pack_delimiter_size = 0
if pack_delimiter then pack_delimiter_size = #pack_delimiter end

local producer = aws.kinesis.simple_producer(clientConfig, credentialProvider, roleArn)


local function get_key()
    local field = read_message(partitionField) or ""
    return string.format("%u", xxhash.h32(field))
end


local function send(p)
    local rv, err = producer:send(streamName, table.concat(p.msgs, pack_delimiter), p.key)
    if rv ~= -3 then
        if rv == -1 and err then
            err = string.format("discarded messages: %d %s", p.cnt, err)
        end
        p.cnt = 0
        p.size = 0
        p.timer = true
        p.msgs = {}
        p.key = nil
    end
    return rv, err
end


function process_message()
    local ok, data = pcall(encode)
    if not ok then return -1, data end
    if not data then return -2 end
    data = tostring(data)
    local dsize = #data
    if dsize > PUT_MAX then return -1, "max message size exceeded" end

    local rv = -4
    local err
    if pack then
        if pack.cnt > 0 then dsize = dsize + pack_delimiter_size end

        if pack.size + dsize > PUT_MAX then
            rv, err = send(pack)
            if rv == -3 then
                return rv, err
            else
                dsize = #data
            end
            pack.timer = false
        end

        pack.cnt = pack.cnt + 1
        pack.msgs[pack.cnt] = data
        pack.size = pack.size + dsize
        if not pack.key then pack.key = get_key() end
        local remainder = pack.size % PUT_UNIT
        if rv ~= -1 and (remainder == 0 or remainder >= pack_percentage) then
            rv, err = send(pack)
            if rv == -3 then
                pack.msgs[pack.cnt] = nil
                pack.cnt = pack.cnt - 1
                pack.size = pack.size - dsize
            end
            pack.timer = false
        end
    else
        rv, err = producer:send(streamName, data, get_key())
    end

    return rv, err
end


function timer_event(ns, shutdown)
    if pack then
        if (shutdown or pack.timer) and pack.cnt > 0 then
            local rv, err = send(pack)
            if rv == 0 then
                update_checkpoint()
            elseif rv == -1 and err then
                print("timer_event", err)
            end
        end
        pack.timer = true
    end
end

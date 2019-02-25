-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# GCP Pub/Sub Subscriber Input

## Sample Configuration
```lua
filename            = "gcp_pubsub.lua"
ticker_interval     = 1
instruction_limit   = 0

channel             = "pubsub.googleapis.com"
project             = "mozilla-data-poc-198117"
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
-- decoder_module = "decoders.payload"
```
--]]

require "gcp.pubsub"
require "string"
local l = require "lpeg"
l.locale(l)

local sdu       = require "lpeg.sub_decoder_util"
local decode    = sdu.load_sub_decoder(read_config("decoder_module") or "decoders.payload", read_config("printf_messages"))

local channel   = read_config("channel") or "pubsub.googleapis.com"
local project   = read_config("project") or error"project must be set"
project         = project:match("^projects/.+") or "projects/" .. project

local topic     = read_config("topic") or error"topic must be set"
topic           = topic:match("^projects/.+") or string.format("%s/topics/%s", project, topic)

local subscription_name = read_config("subscription_name") or string.format("%s_%s", read_config("Hostname"), read_config("Logger"))
subscription_name = string.format("%s/subscriptions/%s", project, subscription_name)

local batch_size = read_config("batch_size") or 1000
assert(batch_size > 0 and batch_size <= 1000)

local max_async_requests = read_config("max_async_requests") or 20
assert(max_async_requests >= 0)

local default_headers = read_config("default_headers") or {}
assert(type(default_headers) == "table", "invalid default_headers type")
if not default_headers.Type then default_headers.Type = topic end

local err_msg = {
    Type    = "error.decode",
    Payload = nil,
    Fields  = {
        data = nil
    }
}

local sep   = l.P"\t"
local str   = l.Cs((1 - (l.P"\\t" + sep) + l.P"\\t" / "\t")^0)
local int   = l.digit^1 / tonumber
local dbl   = (l.digit^1 * (l.P"." * l.digit^1)^-1) / tonumber
local bool  = (l.P"true" + l.P"false") / function(s) return s == "true" end

local function get_array_grammar(elem)
    return l.Ct(elem * (sep * elem)^0)
end

local ktype_lookup  = {
    -- {grammar, value_type}
    _str  = {get_array_grammar(str), 0},
    _int  = {get_array_grammar(int), 2},
    _dbl  = {get_array_grammar(dbl), 3},
    _bool = {get_array_grammar(bool), 4}
}
local ktype_suffix  = (l.P"_int" + l.P"_dbl" + l.P"_bool" + l.Cc"_str") * l.P(-1)
local ktype         = l.C((l.P(1) - ktype_suffix)^1) * (ktype_suffix / ktype_lookup)

local subscriber = gcp.pubsub.subscriber(channel, topic, subscription_name, max_async_requests)
local pull = subscriber.pull
if max_async_requests == 0 then pull = subscriber.pull_sync end
local is_running = is_running
function process_message()
    while is_running() do
        local ok, msgs, cnt = pcall(pull, subscriber, batch_size)
        if not ok then return -1, msgs end

        if cnt > 0 then
            for i=1, cnt do
                local msg = sdu.copy_message(default_headers, false)
                local attrs = msgs[i][2]
                if attrs then
                    if attrs.heka_message then
                        attrs.heka_message = nil
                        msg.Uuid = attrs.Uuid
                        attrs.Uuid = nil
                        msg.Timestamp = int:match(attrs.Timestamp)
                        attrs.Timestamp = nil
                        if attrs.Hostname then
                            msg.Hostname = attrs.Hostname
                            attrs.Hostname = nil
                        end
                        if attrs.Type then
                            msg.Type = attrs.Type
                            attrs.Type = nil
                        end
                        if attrs.Logger then
                            msg.Logger = attrs.Logger
                            attrs.Logger = nil
                        end
                        if attrs.EnvVersion then
                            msg.EnvVersion = attrs.EnvVersion
                            attrs.EnvVersion = nil
                        end
                        if attrs.Severity then
                            msg.Severity = int:match(attrs.Severity)
                            attrs.Severity = nil
                        end
                        if attrs.Pid then
                            msg.Pid = int:match(attrs.Pid)
                            attrs.Pid = nil
                        end
                        local t = {}
                        for k,v in pairs(attrs) do
                            local k, kt = ktype:match(k)
                            v = kt[1]:match(v)
                            if v then
                                t[k] = {value = v, value_type = kt[2]}
                            end
                        end
                        attrs = t
                    end
                    sdu.add_fields(msg, attrs)
                end

                local ok, err = pcall(decode, msgs[i][1], msg, true)
                if not ok or err then
                    err_msg.Payload = err
                    err_msg.Fields.data = data
                    pcall(inject_message, err_msg)
                end
            end
        elseif max_async_requests == 0 then
            break -- poll every ticker_interval
        end
    end
    return 0
end

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Systemd journald Input

## Sample Configuration
```lua
filename        = "journald.lua"
ticker_interval = 1 -- poll once a second after hitting EOF

seek = "tail" -- default (tail|head) location to start if there is no checkpoint

-- Heka message table containing the default header values to use, if they are
-- not populated by the decoder. If 'Fields' is specified it should be in the
-- hashed based format see:  http://mozilla-services.github.io/lua_sandbox/heka/message.html
-- This input will always default the Type header to the Kafka topic name.
-- Default:
-- default_headers = nil

-- printf_messages = -- see: https://mozilla-services.github.io/lua_sandbox_extensions/lpeg/modules/lpeg/printf.html

-- Specifies a hash keyed by _TRANSPORT. Each transport specifies its own sub decoder hash configuration keyed
-- by SYSLOG_IDENTIFIER.
-- see: https://mozilla-services.github.io/lua_sandbox_extensions/lpeg/io_modules/lpeg/sub_decoder_util.html
-- Default:
decoders = nil

-- example to perform additional parsing on the syslog/sshd message contents
--decoders = {
--    syslog  = {
--        printf_messages = {
--            "lpeg.openssh_portable",
--        },
--        sub_decoders = {
--            sshd =  {
--            "Accepted publickey for foobar from 192.168.1.1 port 4567 ssh2",
--            },
--            filterlog = "lpeg.bsd.filterlog",
--        }
--    },
--    --audit   = {},
--    --driver  = {},
--    --journal = {},
--    --stdout  = {},
--    --kernel  = {},
--}
```
--]]

local sj    = require "systemd.journal"
local sdu   = require "lpeg.sub_decoder_util"

local seek              = read_config("seek") or "tail"
local default_headers   = read_config("default_headers")
local transports = {}
for k,v in pairs(read_config("decoders") or {}) do
    transports[k] = sdu.load_sub_decoders(v.sub_decoders, v.printf_messages)
end

local err_msg = {
    Type    = "error.decode",
    Payload = nil,
    Fields  = {
        data = nil
    }
}

local fh
function process_message(checkpoint)
    if not fh then
        fh = assert(sj.open())
        if checkpoint then
            fh:seek_cursor(checkpoint)
        else
            if seek == "head" then
                fh:seek_head()
            else
                fh:seek_tail()
            end
        end
    end

    while true do
        local found = fh:next()
        if not found then return 0 end

        local fields = {}
        while true do
            local found, value = fh:enumerate_data()
            if not found then break end
            local k, v = value:match("(.+)=(.*)")
            if k then
                local f = fields[k]
                if f then -- support duplicate keys as an array
                    if type(f) ~= "table" then
                        fields[k] = {f, v}
                    else
                        f[#f + 1] = v
                    end
                else
                    fields[k] = v
                end
            end
        end

        local msg = sdu.copy_message(default_headers, false)
        sdu.add_fields(msg, fields)
        local transport = transports[fields._TRANSPORT]
        if transport then
            local df = transport[fields.SYSLOG_IDENTIFIER]
            if df then
                local data = fields.MESSAGE
                msg.Fields.MESSAGE = nil
                local ok, err = pcall(df, data, msg, true)
                if (not ok or err) and send_decode_failures then
                    err_msg.Payload = string.format("%s.%s %s", fields._TRANSPORT, fields.SYSLOG_IDENTIFIER, err)
                    pcall(inject_message, err_msg)
                end
                inject_message(nil, fh:get_cursor())
            else
                local ok, err = pcall(inject_message, msg, fh:get_cursor())
                if not ok then return -1, err end
            end
        else
            local ok, err = pcall(inject_message, msg, fh:get_cursor())
            if not ok then return -1, err end
        end
    end
    return 0
end

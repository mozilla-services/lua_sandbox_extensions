-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Tail File Input (new line delimited)
todo: when more than line splitting is needed the file should be read in chunks
and passed to a generic splitter buffer with a token/match specification and a
find function similar to the Heka stream reader.

## Sample Configuration
```lua
filename = "tail.lua"
ticker_interval = 1 -- poll once a second after hitting EOF

-- Name of the input file
input_filename = "/var/log/text.log"

-- Multi-line log support
-- delimiter = "^# User@Host:" -- optional if anchored at the beginning of the line it is treated as
                               -- a start of record delimiter and the line belongs to the next log
                               -- otherwise it is an end of record delimiter and the line belongs to
                               -- the current log. "^$" is special cased and is treated as an end of
                               -- line delimiter.
-- Consumes appended data as the file grows
-- Default:
-- follow = "descriptor" -- use "name" for rotated logs

-- Heka message table containing the default header values to use, if they are
-- not populated by the decoder. If 'Fields' is specified it should be in the
-- hashed based format see:  http://mozilla-services.github.io/lua_sandbox/heka/message.html
-- Default:
-- default_headers = nil

-- printf_messages = -- see: https://mozilla-services.github.io/lua_sandbox_extensions/lpeg/modules/lpeg/printf.html

-- Specifies a module that will decode the raw data and inject the resulting message.
-- Supports the same syntax as an individual sub decoder
-- see: https://mozilla-services.github.io/lua_sandbox_extensions/lpeg/io_modules/lpeg/sub_decoder_util.html
-- Default:
-- decoder_module = "decoders.payload"

-- Boolean, if true, any decode failure will inject a  message of Type "error",
-- with the Payload containing the error.
-- Default:
-- send_decode_failures = false
```
--]]
require "io"
require "string"
local sdu       = require "lpeg.sub_decoder_util"
local decode    = sdu.load_sub_decoder(read_config("decoder_module") or "decoders.payload", read_config("printf_messages"))

local input_filename  = read_config("input_filename") or error("input_filename is required")
local follow = read_config("follow") or "descriptor"
assert(follow == "descriptor" or follow == "name", "invalid follow cfg")

local default_headers = read_config("default_headers")
assert(default_headers == nil or type(default_headers) == "table", "invalid default_headers cfg")

local send_decode_failures  = read_config("send_decode_failures")
local delimiter = read_config("delimiter")

local err_msg = {
    Type    = "error.decode",
    Payload = nil,
    Fields  = {
        data = nil
    }
}

local read_until_eof
local function flush_remaining() return end
if delimiter then
    local concat = require "table".concat
    local start_delimiter = delimiter:match("^^") and delimiter ~= "^$"
    local buffer
    local buffer_idx
    local buffer_size

    local function reset_buffer()
        buffer            = {}
        buffer_idx        = 0
        buffer_size       = 0
    end
    reset_buffer()

    function read_until_eof(fh, checkpoint)
        for data in fh:lines() do
            if data:match(delimiter) then
                if not start_delimiter then
                    buffer_idx = buffer_idx + 1
                    buffer[buffer_idx] = data
                    buffer_size = buffer_size + #data + 1
                end

                local line = concat(buffer, "\n")
                local ok, err = pcall(decode, line, default_headers)
                if (not ok or err) and send_decode_failures then
                    err_msg.Payload = err
                    err_msg.Fields.data = line
                    pcall(inject_message, err_msg)
                end
                checkpoint = checkpoint + buffer_size
                inject_message(nil, checkpoint)
                reset_buffer()

                if start_delimiter then
                    buffer_idx = 1
                    buffer[buffer_idx] = data
                    buffer_size = #data + 1
                end
            else
                buffer_idx = buffer_idx + 1
                buffer[buffer_idx] = data
                buffer_size = buffer_size + #data + 1
            end
        end
    end

    function flush_remaining()
        if buffer_idx == 0 then return end
        local line = concat(buffer, "\n")
        local ok, err = pcall(decode, line, default_headers)
        if (not ok or err) and send_decode_failures then
            err_msg.Payload = err
            err_msg.Fields.data = line
            pcall(inject_message, err_msg)
        end
        reset_buffer()
    end

else
    function read_until_eof(fh, checkpoint)
        for data in fh:lines() do
            local ok, err = pcall(decode, data, default_headers)
            if (not ok or err) and send_decode_failures then
                err_msg.Payload = err
                pcall(inject_message, err_msg)
            end
            checkpoint = checkpoint + #data + 1
            inject_message(nil, checkpoint)
        end
    end
end


local function open_file(checkpoint)
    local fh, err = io.open(input_filename, "rb")
    if not fh then return nil end

    if checkpoint ~= 0 then
        if not fh:seek("set", checkpoint) then
            print("invalid checkpoint, starting from the beginning")
            checkpoint = 0
            inject_message(nil, checkpoint)
        end
    end
    return fh
end


local function get_inode()
    return lfs.attributes(input_filename, "ino")
end


local inode
local function follow_name(fh, checkpoint)
    if not inode then inode = get_inode() end
    while true do
        read_until_eof(fh, checkpoint)
        local tinode = get_inode()
        if inode ~= tinode then
            flush_remaining()
            inode = tinode
            checkpoint = 0
            inject_message(nil, checkpoint)
            fh:close()
            if not tinode then return nil end

            fh = open_file(checkpoint)
            if not fh then return nil end
        else
            return fh -- poll
        end
    end
end


local function follow_descriptor(fh, checkpoint)
    read_until_eof(fh, checkpoint)
    return fh -- poll
end


if follow == "name" then
    require "lfs"
    follow = follow_name
else
    follow = follow_descriptor
end


local fh
function process_message(checkpoint)
    checkpoint = checkpoint or 0
    if not fh then
        fh = open_file(checkpoint)
        if not fh then
            if checkpoint ~= 0 then
                print("file not found resetting the checkpoint to 0")
                inject_message(nil, 0)
            end
            return 0
        end
    end
    fh = follow(fh, checkpoint)
    return 0
end

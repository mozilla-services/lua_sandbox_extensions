-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Single File Input (new line delimited)
todo: when more than line splitting is needed the file should be read in chunks
and passed to a generic splitter buffer with a token/match specification and a
find function similar to the Heka stream reader.

## Sample Configuration
```lua
filename = "file.lua"

-- Name of the input file (nil for stdin)
-- Default:
-- input_filename = nil

-- Multi-line log support
-- delimiter = "^# User@Host:" -- optional if anchored at the beginning of the line it is treated as
                               -- a start of record delimiter and the line belongs to the next log
                               -- otherwise it is an end of record delimiter and the line belongs to
                               -- the current log. "^$" is special cased and is treated as an end of
                               -- line delimiter.

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

local input_filename  = read_config("input_filename")
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

local read_file
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

    local function append_data(data)
        buffer_idx = buffer_idx + 1
        buffer[buffer_idx] = data
        buffer_size = buffer_size + #data + 1
    end

    local rec = 0
    local function decode_record(checkpoint)
        local line = concat(buffer, "\n")
        local ok, err = pcall(decode, line, default_headers)
        if (not ok or err) then
            if send_decode_failures then
                err_msg.Payload = err
                err_msg.Fields.data = line
                pcall(inject_message, err_msg)
            end
        else
            rec = rec + 1
        end

        if input_filename then
            checkpoint = checkpoint + buffer_size
            inject_message(nil, checkpoint)
        end
        reset_buffer()
        return checkpoint
    end

    read_file = function(fh, checkpoint)
        local cnt = 0
        for data in fh:lines() do
            if data:match(delimiter) then
                if not start_delimiter then append_data(data) end
                checkpoint = decode_record(checkpoint)
                if start_delimiter then append_data(data) end
            else
                append_data(data)
            end
            cnt = cnt + 1
        end
        if buffer_idx ~= 0 then decode_record(checkpoint) end
        return string.format("processed %d lines %d records", cnt, rec)
    end
else
    read_file = function(fh, checkpoint)
        local cnt = 0
        for data in fh:lines() do
            local ok, err = pcall(decode, data, default_headers)
            if (not ok or err) and send_decode_failures then
                err_msg.Payload = err
                err_msg.Fields.data = data
                pcall(inject_message, err_msg)
            end

            if input_filename then
                checkpoint = checkpoint + #data + 1
                inject_message(nil, checkpoint)
            end
            cnt = cnt + 1
        end
        return string.format("processed %d lines", cnt)
    end
end


function process_message(checkpoint)
    local fh = io.stdin
    if input_filename then
        fh = assert(io.open(input_filename, "rb")) -- closed on plugin shutdown
        if checkpoint then
            fh:seek("set", checkpoint)
        else
            checkpoint = 0
        end
    end
    return 0, read_file(fh, checkpoint)
end

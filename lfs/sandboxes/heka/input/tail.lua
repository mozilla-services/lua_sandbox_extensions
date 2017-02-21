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
input_filename = /var/log/text.log

-- Consumes appended data as the file grows
-- Default:
-- follow = "descriptor" -- use "name" for rotated logs

-- Heka message table containing the default header values to use, if they are
-- not populated by the decoder. If 'Fields' is specified it should be in the
-- hashed based format see:  http://mozilla-services.github.io/lua_sandbox/heka/message.html
-- Default:
-- default_headers = nil

-- Specifies a module that will decode the raw data and inject the resulting message.
-- Default:
-- decoder_module = "decoders.payload"

-- Boolean, if true, any decode failure will inject a  message of Type "error",
-- with the Payload containing the error.
-- Default:
-- send_decode_failures = false
```
--]]
require "io"

local input_filename  = read_config("input_filename") or error("input_filename is required")
local follow = read_config("follow") or "descriptor"
assert(follow == "descriptor" or follow == "name", "invalid follow cfg")

local default_headers = read_config("default_headers")
assert(default_headers == nil or type(default_headers) == "table", "invalid default_headers cfg")

local decoder_module  = read_config("decoder_module") or "decoders.payload"
local decode          = require(decoder_module).decode
if not decode then
    error(decoder_module .. " does not provide a decode function")
end
local send_decode_failures  = read_config("send_decode_failures")

local err_msg = {
    Type    = "error",
    Payload = nil,
}

local function read_until_eof(fh, checkpoint)
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

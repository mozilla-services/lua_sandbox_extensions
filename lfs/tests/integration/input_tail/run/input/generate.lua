-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "io"
require "os"
require "string"
local socket = require "socket"

local function open_log()
    local fh = assert(io.open("output/rotate.log", "w+"))
    return fh
end

local load_path = read_config("sandbox_load_path")
local fn = string.format("%s/input/rotate.cfg", load_path)
local fh = assert(io.open(fn, "w+"))
fh:write([[filename = "tail.lua"
input_filename = "output/rotate.log"
follow = "name"
decoder_module  = "decoders.payload"
ticker_interval = 1
]])
fh:close()

fn = string.format("%s/input/multiline.cfg", load_path)
fh = assert(io.open(fn, "w+"))
fh:write([[filename = "tail.lua"
input_filename = "multiline.log"
delimiter = "^$"
decoder_module  = "decoders.payload"
]])
fh:close()

fn = string.format("%s/input/singleline.cfg", load_path)
fh = assert(io.open(fn, "w+"))
fh:write([[filename = "tail.lua"
input_filename = "singleline.log"
decoder_module  = "decoders.payload"
]])
fh:close()

function process_message()
    socket.sleep(3)
    fh = open_log()
    fh:write("log 1 line one\nlog 1 start of line two")
    fh:flush()
    -- fh:write(" end of line two\n") -- tail will incorrectly return the partial line tow
    socket.sleep(1)
    os.execute("mv output/rotate.log output/rotate.log.0")
    fh = open_log()
    fh:write("log 2 line one\n")
    fh:close()
    return 0
end

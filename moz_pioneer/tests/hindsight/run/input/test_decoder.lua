-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Consumes the test data for moz_pioneer JSOE decoder
--]]

require "io"
require "string"

local decode = require("decoders.moz_pioneer.jose").decode

local hsr = create_stream_reader(read_config("Logger"))
local is_running = is_running

function process_message()
    fh = assert(io.open("input.hpb", "rb")) -- closed on plugin shutdown

    local found, bytes, read
    local cnt = 0
    local consumed = 0
    repeat
        repeat
            found, bytes, read = hsr:find_message(fh)
            if found then
                decode(hsr:read_message("raw")) -- this re-parse is just an artifact of the test setup
                cnt = cnt + 1
            end
        until not found
    until read == 0 or not is_running()
    return 0, string.format("processed %d messages", cnt)
end

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Consumes the test data for moz_ingest common/pioneer decoder
--]]

require "io"
require "string"

local tm = require("decoders.moz_ingest.common").transform_message

local hsr = create_stream_reader(read_config("Logger"))
local is_running = is_running

local errors = {
    "missing uri",
    "invalid uri"
}

function process_message()
    fh = assert(io.open("input.hpb", "rb")) -- closed on plugin shutdown

    local found, bytes, read
    local cnt = 0
    local err_cnt = 0
    repeat
        repeat
            found, bytes, read = hsr:find_message(fh)
            if found then
                local ok, err = pcall(tm, hsr)
                if err then
                    err_cnt = err_cnt + 1
                    if errors[err_cnt] ~= err then
                        error(string.format("err_cnt: %d err: %s", err_cnt, err))
                    end
                end
                cnt = cnt + 1
            end
        until not found
    until read == 0 or not is_running()
    return 0, string.format("processed %d messages", cnt)
end

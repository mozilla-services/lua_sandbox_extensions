-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Protobuf Single File Input

## Sample Configuration
```lua
filename = "heka_file.lua"

-- Name of the input file (nil for stdin)
-- Default:
-- input_filename = nil

```
--]]
require "io"
require "string"

local input_filename = read_config("input_filename")
local hsr = create_stream_reader(read_config("Logger"))
local is_running = is_running

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

    local found, bytes, read
    local cnt = 0
    local consumed = 0
    repeat
        repeat
            found, bytes, read = hsr:find_message(fh)
            if found then
                if input_filename then
                    consumed = consumed + bytes
                    inject_message(hsr, consumed)
                else
                    inject_message(hsr)
                end
                cnt = cnt + 1
            end
        until not found
    until read == 0 or not is_running()
    return 0, string.format("processed %d messages", cnt)
end

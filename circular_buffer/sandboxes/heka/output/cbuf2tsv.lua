-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Circular Buffer to TSV Output

## Sample Configuration
```lua
filename    = "cbuf2tsv.lua"
output_path = /var/www/example.com/cbufs -- path to write the converted cbuf(s) to
```

## Sample Input
```
{"time":1423440000,"rows":4,"columns":1,"seconds_per_row":1,"column_info":[{"name":"Active_Users","unit":"count","aggregation":"sum"}]}
33031
33526
40143
38518
```

## Sample Output
```
Time (time_t)    Active Users (count)
1423440000  33031
1423440001  33526
1423440002  40143
1423440003  38518
```
--]]

require "cjson"
require "io"
require "string"
require "table"

local output_path = assert(read_config("output_path"), "output_path must be specified")

function process_message()
    local header
    local cb_time = 0
    local cb_spr = 0
    local cb_rows = 0
    local body = {}
    local cnt = 0

    local payload = read_message("Payload")
    for l in string.gmatch(payload, ".-\n") do
        if not header then
            if string.match(l, "^{") then
                local ok, json = pcall(cjson.decode, l)
                if not ok then return -1, json end

                if type(json.time) == "number" and
                type(json.rows) == "number" and
                type(json.seconds_per_row) == "number" and
                type(json.column_info) == "table" then
                    cb_time = json.time
                    cb_spr = json.seconds_per_row
                    cb_rows = json.rows
                    local names = {"Time (time_t)"}
                    for i, v in ipairs(json.column_info) do
                        local ok, col = pcall(string.format, "%s (%s)", v.name, v.unit)
                        if not ok then return -1, "invalid column_info" end
                        names[i + 1] = col
                    end
                    header = table.concat(names, "\t")
                end
            end
        else
            cnt = cnt + 1
            body[cnt] = string.format("%d\t%s", (cnt - 1) * cb_spr + cb_time, l)
        end
    end

    if not header then return -1, "malformed cbuf, no header" end

    if cnt < 3 or cnt ~= cb_rows then
        return -1, string.format("incorrect number of rows expected: %d, received: %d", cb_rows, cnt)
    end

    local logger = read_message("Logger")

    local name = read_message("Fields[payload_name]") or ""
    name = string.gsub(name, "%W", "")
    if string.len(name) > 64 then name = string.sub(name, 1, 64) end

    local fh = assert(io.open(string.format("%s/%s.%s.tsv", output_path, logger, name), "w"))
    fh:write(header, "\n", table.concat(body))
    fh:close()
    return 0
end

function timer_event(ns)
    -- used to force GC
end

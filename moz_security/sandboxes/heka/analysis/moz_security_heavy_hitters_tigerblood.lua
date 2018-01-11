-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
#  Mozilla Security Heavy Hitters for Tigerblood

See: https://cacm.acm.org/magazines/2009/10/42481-finding-the-frequent-items-in-streams-of-data/abstract

This is a version of the heavy hitters plugin that generates violation messages
to forward to Tigerblood vs heka_payload TSV output.

## Sample Configuration
```lua
filename = "moz_security_heavy_hitters_tigerblood.lua"
message_matcher = "Logger == 'input.nginx'"
ticker_interval = 60
preserve_data = true

id_field = "Fields[remote_addr]"
-- id_field_capture = ",? *([^,]+)$"a -- optional e.g. extract the last entry in a comma delimited list
-- hh_items = 10000 -- optional, defaults to 10000 (maximum number of heavy hitter IDs to track)

violation_type = "fxa:heavy-hitter-ip" -- IP reputation violation type to lookup reputation penalty for
```
--]]
require "string"

local tb = require "heka.tigerblood"

local id_field  = read_config("id_field") or error("id_field must be configured")
local id_fieldc = read_config("id_field_capture")
local hh_items  = read_config("hh_items") or 10000

local violation_type = read_config("violation_type") or error("No ip violation type specified")

hh = {}
hh_size = 0

function process_message()
    local id = read_message(id_field)
    if not id then return -1, "no id_field" end
    if id_fieldc then
        id = string.match(id, id_fieldc)
        if not id then return 0 end -- no error as the capture may intentionally reject entries
    end

    local cnt = hh[id]
    if cnt then
        hh[id] = cnt + 1
    else
        if hh_size >= hh_items then
            for k, cnt in pairs(hh) do
                cnt = cnt - 1
                if 0 == cnt then
                    hh[k] = nil
                    hh_size = hh_size - 1
                else
                    hh[k] = cnt
                end
            end
        else
            hh_size = hh_size + 1
            hh[id] = 1
        end
    end
    return 0
end

function timer_event(ns)
    local violations = {}
    local i = 1;

    for ip, cnt in pairs(hh) do
        if (cnt > 5 and ip ~= "-") then
            violations[i] = {ip=ip, violation=violation_type, weight=cnt}
            i = i + 1
        end
    end

    tb.send(violations)
end

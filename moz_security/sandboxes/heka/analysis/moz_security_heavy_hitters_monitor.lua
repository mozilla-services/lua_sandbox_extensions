-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
#  Mozilla Security Heavy Hitters Monitor

See: https://cacm.acm.org/magazines/2009/10/42481-finding-the-frequent-items-in-streams-of-data/abstract

## Sample Configuration
```lua
filename = "moz_security_heavy_hitters.lua"
message_matcher = "Logger == 'input.nginx'"
ticker_interval = 60

id_field = "Fields[remote_addr]"
-- hh_items = 1000 -- optional, defaults to 1000 (maximum number of heavy hitter IDs to track)

cf_items = 100e6
-- cf_interval_size = 1, -- optional, default 1 (256 minutes)

-- update if altering the cf_* configuration of an existing plugin
preservation_version = 0
preserve_data = true

alert = {
    prefix = true,
    throttle = 1,
    modules = {
        email = {recipients = {"pagerduty@mozilla.com"}}
    }
}
```
--]]
_PRESERVATION_VERSION = read_config("preservation_version") or _PRESERVATION_VERSION or 0

require "cuckoo_filter_expire"
-- local alert = require "heka.alert" -- todo define alerting

local id_field = read_config("id_field") or error("id_field must be configured")
local hh_items = read_config("hh_items") or 1000
local cf_items = read_config("cf_items") or error("cf_items must be configured")
local cf_interval_size = read_config("cf_interval_size") or 1

cf = cuckoo_filter_expire.new(cf_items, 1)
hh = {}
hh_size = 0

function process_message()
    local id = read_message(id_field)
    if not id then return -1, "no id_field" end

    local ns = read_message("Timestamp")
    local added = cf:add(id, ns)
    if not added then
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
    end
    return 0
end


function timer_event(ns)
    for k, cnt in pairs(hh) do
        if cnt > 1 then
            add_to_payload(cnt, "\t", k, "\n")
        end
    end
    inject_payload("tsv", "alltime")
end

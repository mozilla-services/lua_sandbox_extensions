-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Security Heavy Hitters

For events matching the message_matcher, this analysis plugin identifies the number of events
seen for a given identification field (e.g., the IP address in an nginx log). Can be utilized to trend
heavy usage from specific identifiers. Event counts per identifier are stored in a count-min sketch.

During each ticker interval, the plugin calculates the average requests per identifier within the
window (event frequency); identifiers that have made requests that exceeed the average + the calculated
threshold cap will be captured in the plugin output. Note the threshold is calculated on each interval
using the formula shown in the sample configuration.

The plugin by default outputs collected data as TSV; if the send_iprepd configuration option
is enabled the plugin will instead output data as iprepd violation messages (for consumption by
for example the iprepd output module).

Heavy hitters will be identified on each interval tick, so ensure the ticker_interval parameter is
set to a value appropriate for consumption of the intended event stream to ensure the gathered sample
is sufficient.

## Sample Configuration
```lua
filename = "moz_security_heavy_hitters.lua"
message_matcher = "Logger == 'input.nginx'"
ticker_interval = 60
preserve_data = false

id_field = "Fields[remote_addr]" -- field to use as the identifier
-- id_field_capture = ",? *([^,]+)$",  -- optional e.g. extract the last entry in a comma delimited list

-- list_max_size = 10000 -- optional, defaults to 10000 (maximum number of heavy hitter IDs to track)
-- send_iprepd = false -- optional, if true plugin will generate iprepd violation messages
-- violation_type = "fxa:heavy_hitter_ip" -- required in violations mode, iprepd violation type

threshold_cap = 10 -- Threshold will be calculated average + (calculated average * cap)
-- threshold_min = 100 -- optional calculated threshold minimum otherwise ignore interval
-- cms_epsilon = 1 / 10000 -- optional CMS value for epsilon
-- cms_delta = 0.0001 -- optional CMS value for delta
```
--]]

require "string"
require "table"

local HUGE      = require "math".huge
local ostime    = require "os".time

local threshold_cap = read_config("threshold_cap") or error("threshold_cap must be configured")
local threshold_min = read_config("threshold_min")
local id_field      = read_config("id_field") or error("id_field must be configured")
local id_fieldc     = read_config("id_field_capture")
local cms_epsilon   = read_config("cms_epsilon") or 1 / 10000
local cms_delta     = read_config("cms_delta") or 0.0001
local list_max_size = read_config("list_max_size") or 10000

local tbsend
local violation_type
local send_iprepd = read_config("send_iprepd")
if send_iprepd then
    tbsend = require "heka.iprepd".send
    violation_type = read_config("violation_type") or error("violation_type must be configured")
end

local cms = require "streaming_algorithms.cm_sketch".new(cms_epsilon, cms_delta)

local threshold

local list = {}
local list_size = 0
local list_min = HUGE
local list_min_id = nil

local function find_min()
    list_min = HUGE
    for k,v in pairs(list) do
        if v < list_min then
            list_min = v
            list_min_id = k
        end
    end
end


local function calc_threshold()
    threshold = cms:item_count() / cms:unique_count()
    threshold = threshold + (threshold * threshold_cap)
end


function process_message()
    local id = read_message(id_field)
    if not id then return -1, "no id_field" end
    if id_fieldc then
        id = string.match(id, id_fieldc)
        if not id then return 0 end -- no error as the capture may intentionally reject entries
    end

    local c = cms:update(id)

    if c > list_min or list_size < list_max_size then
        if list[id] then
            list[id] = c
            if list_min_id == id then find_min() end
        elseif list_size < list_max_size then
            list[id] = c
            list_size = list_size + 1
            if c < list_min then
                list_min = c
                list_min_id = id
            end
        else
            list[list_min_id] = nil
            list[id] = c
            find_min()
        end
    end

    return 0
end


function clear_list()
    list = {}
    list_size = 0
    list_min = HUGE
    list_min_id = nil
    cms:clear()
end


function timer_event(ns)
    local slist = {}
    for n in pairs(list) do table.insert(slist, n) end
    table.sort(slist)

    calc_threshold()
    local low_threshold = false
    if threshold_min and threshold < threshold_min then low_threshold = true end

    if not send_iprepd then
        add_to_payload("threshold", "\t", threshold, "\n")
        add_to_payload("list_size", "\t", cms:unique_count(), "\n")
        add_to_payload("event_count", "\t", cms:item_count(), "\n")
        add_to_payload("low_threshold", "\t", low_threshold, "\n")
    end

    if low_threshold then
        if not send_iprepd then inject_payload("tsv", "statistics") end
        clear_list()
        return
    end

    local violations = {}
    local vindex = 1
    for i,ip in ipairs(slist) do
        local cnt = list[ip]
        if cnt > threshold then
            if not send_iprepd then
                add_to_payload(ip, "\t", cnt, "\n")
            else
                violations[vindex] = {ip = ip, violation = violation_type}
                vindex = vindex + 1
            end
        end
    end

    if not send_iprepd then
        inject_payload("tsv", "statistics")
    else
        tbsend(violations)
    end

    clear_list()
end

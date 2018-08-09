-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Security Client Error Rate

For events matching the message_matcher, this analysis plugin identifies the number of events
seen for a given identification field (e.g., the IP address in an nginx log) that have resulted
in an HTTP client error code (e.g., >= 400, < 500).

Any clients that have exceeded error_threshold errors in a given ticker interval will be added
to a list that is processed during the timer event.

If send_iprepd is true, violation messages will be generated for the iprepd output plugin using the
specified violation_type. If send_iprepd is false, TSV output will be created containing the violation
list for the ticker interval.

If enable_metrics is true, the module will submit metrics events for collection by the metrics
output sandbox. Ensure timer_event_inject_limit is set appropriately, as if enabled timer_event
will submit up to 2 messages (the violation notice, and the metric event).

## Sample Configuration
```lua
filename = "moz_security_http_error_rate.lua"
message_matcher = "Logger == 'input.nginx'"
ticker_interval = 60
preserve_data = false

id_field = "Fields[remote_addr]" -- field to use as the identifier
-- id_field_capture = ",? *([^,]+)$",  -- optional e.g. extract the last entry in a comma delimited list
code_field = "Fields[code]" -- field to extract HTTP status code from

-- list_max_size = 500 -- optional, defaults to 500 (maximum number of clients that can be flagged per tick)
-- send_iprepd = false -- optional, if true plugin will generate iprepd violation messages
-- violation_type = "fxa:client_error_rate" -- required in violations mode, iprepd violation type
error_threshold = 50 -- clients generating over error_threshold client errors will be tracked

-- cms_epsilon = 1 / 10000 -- optional CMS value for epsilon
-- cms_delta = 0.0001 -- optional CMS value for delta

-- enable_metrics = false -- optional, if true enable secmetrics submission
```
--]]

require "table"
require "string"

local error_threshold   = read_config("error_threshold") or error("error_threshold must be configured")
local id_field          = read_config("id_field") or error("id_field must be configured")
local id_fieldc         = read_config("id_field_capture")
local code_field        = read_config("code_field") or error("code_field must be configured")
local cms_epsilon       = read_config("cms_epsilon") or 1 / 10000
local cms_delta         = read_config("cms_delta") or 0.0001
local list_max_size     = read_config("list_max_size") or 500

local tbsend
local violation_type
local send_iprepd = read_config("send_iprepd")
if send_iprepd then
    tbsend = require "heka.iprepd".send
    violation_type = read_config("violation_type") or error("violation_type must be configured")
end

local cms = require "streaming_algorithms.cm_sketch".new(cms_epsilon, cms_delta)

local secm
if read_config("enable_metrics") then
    secm = require "heka.secmetrics".new()
end

local list = {}
local list_size = 0

function process_message()
    -- if the list in this interval is already full, return here and wait for the next
    -- timer event to clear it
    if list_size >= list_max_size then return 0 end

    local code = read_message(code_field)
    if not code then return -1, "no code_field" end
    if code < 400 or code >= 500 then return 0 end -- only client errors

    local id = read_message(id_field)
    if not id then return -1, "no id_field" end
    if id_fieldc then
        id = string.match(id, id_fieldc)
        if not id then return 0 end -- no error as the capture may intentionally reject entries
    end

    if secm then secm:inc_accumulator("processed_events") end
    local c = cms:update(id)
    if c < error_threshold then return 0 end

    if not list[id] then list_size = list_size + 1 end
    list[id] = c

    return 0
end

function timer_event(ns)
    local slist = {}
    for n in pairs(list) do table.insert(slist, n) end
    table.sort(slist)

    if not send_iprepd then
        add_to_payload("error_threshold", "\t", error_threshold, "\n")
        add_to_payload("cms_size", "\t", cms:unique_count(), "\n")
    end

    local violations = {}
    for i,ip in ipairs(slist) do
        local cnt = list[ip]
        if not send_iprepd then
            add_to_payload(ip, "\t", cnt, "\n")
        else
            if secm then
                secm:inc_accumulator("violations_sent")
                secm:add_uniqitem("unique_violations", violation_type)
            end
            violations[i] = {ip = ip, violation = violation_type}
        end
    end

    if not send_iprepd then
        inject_payload("tsv", "statistics")
    else
        tbsend(violations)
    end
    if secm then secm:send() end

    list = {}
    list_size = 0
    cms:clear()
end

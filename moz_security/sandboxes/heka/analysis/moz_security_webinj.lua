-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Security libinjection processing for request events

For events matching the message matcher, apply SQLi and XSS detection using
libinjection to request_field.

request_field should contain the URI to be analyzed, including it's parameters.
For example "http://example.host/test?arg=value".

If request_field contains more than just the URI (for example, it may also contain
the HTTP method and protocol as is common with web server logs) then the
request_field_capture configuration can be set to provide a capture on request_field
to get the desired substring.

Where XSS/SQLi is detected by libinjection, an entry is added to a list that is
processed during the tick interval. This can result in either TSV output being submitted
or if send_iprepd is enabled, violation messages being generated for IP addresses
associated with the findings.

If enable_metrics is true, the module will submit metrics events for collection by the metrics
output sandbox. Ensure timer_event_inject_limit is set appropriately, as if enabled timer_event
will submit up to 2 messages (the violation notice, and the metric event).

## Sample Configuration
```lua
filename = "moz_security_webinj.lua"
message_matcher = "Logger == 'input.nginx'"
ticker_interval = 120
preserve_data = false

id_field = "Fields[remote_addr]" -- field to use as the identifier (e.g., remote address)
-- id_field_capture = ",? *([^,]+)$",  -- optional e.g. extract the last entry in a comma delimited list
request_field = "Fields[request] -- field containing HTTP request
-- request_field_capture = "%S+%s+(%S+)" -- optional, e.g., extract second string in field
-- list_max_size = 500 -- optional, defaults to 500 if unset
-- strip_nul = true -- optional, strip %00 prior to inspection, defaults to false

-- send_iprepd = false -- optional, if true plugin will generate iprepd violation messages
-- xss_violation_type = "fxa:webinj_xss" -- required in violations mode, iprepd violation type
-- sqli_violation_type = "fxa:webinj_sqli" -- required in violations mode, iprepd violation type

-- enable_metrics = false -- optional, if true enable secmetrics submission
```
--]]

require "string"
require "table"

local libi    = require "libinjection"
local uri     = require "lpeg.uri"

local id_field          = read_config("id_field") or error("id_field must be configured")
local id_fieldc         = read_config("id_field_capture")
local request_field     = read_config("request_field") or error("request_field must be configured")
local request_fieldc    = read_config("request_field_capture")
local list_max_size     = read_config("list_max_size") or 500
local strip_nul         = read_config("strip_nul")

local tbsend
local violation_type
local send_iprepd = read_config("send_iprepd")
if send_iprepd then
    tbsend = require "heka.iprepd".send
    xss_violation_type = read_config("xss_violation_type") or error("xss_violation_type must be configured")
    sqli_violation_type = read_config("sqli_violation_type") or error("sqli_violation_type must be configured")
end

local secm
if read_config("enable_metrics") then
    secm = require "heka.secmetrics".new()
end

local list = {}
local list_size = 0

function process_message()
    if list_size >= list_max_size then
        return 0 -- list full, stop analyzing until the next timer interval
    end

    local id = read_message(id_field)
    if not id then return -1, "no id_field" end
    if id_fieldc then
        id = string.match(id, id_fieldc)
        if not id then return 0 end -- no error as the capture may intentionally reject entries
    end
    local orig_req = read_message(request_field)
    if not orig_req then return -1, "no request_field" end
    local req = orig_req
    if request_fieldc then
        req = string.match(req, request_fieldc)
        if not req then return 0 end -- no error as the capture may intentionally reject entries
    end
    if strip_nul then req = string.gsub(req, "%%00", "") end

    if secm then secm:inc_accumulator("processed_events") end
    local m = uri.uri_reference:match(req)
    if not m or not m.query then return 0 end
    local params = uri.url_query:match(m.query)
    if not params then return 0 end -- ignore query string that is just an = or &

    local foundtype = nil
    for k,v in pairs(params) do
        if libi.xss(v, string.len(v)) == 1 then
            foundtype = "xss"
        else
            local state = libi.sqli_state()
            if not state then return -1, "error allocating sqli state" end
            libi.sqli_init(state, v, string.len(v), 0)
            if libi.is_sqli(state) == 1 then
                foundtype = "sqli"
            end
        end
    end

    if foundtype then
        local t = list[id]
        if not t then
            t = {
                cnt         = 0,
                lastsqli    = nil,
                lastxss     = nil,
            }
            list[id] = t
            list_size = list_size + 1
        end
        if foundtype == "xss" then
            t.lastxss = orig_req
            if secm then
                secm:inc_accumulator("detect_xss")
                secm:add_uniqitem("xss_unique_host", id)
            end
        else
            t.lastsqli = orig_req
            if secm then
                secm:inc_accumulator("detect_sqli")
                secm:add_uniqitem("sqli_unique_host", id)
            end
        end
        t.cnt = list[id].cnt + 1
    end

    return 0
end

function timer_event(ns)
    local slist = {}
    for n in pairs(list) do table.insert(slist, n) end
    table.sort(slist)

    local violations = {}
    local vindex = 1
    for i,ip in ipairs(slist) do
        local c = list[ip]
        if not send_iprepd then
            add_to_payload(ip, "\t", c.cnt, "\t", c.lastxss, "\t",
                c.lastsqli, "\n")
        else
            if c.lastxss then
                if secm then secm:inc_accumulator("violations_sent") end
                violations[vindex] = {ip = ip, violation = xss_violation_type}
                vindex = vindex + 1
            end
            if c.lastsqli then
                if secm then secm:inc_accumulator("violations_sent") end
                violations[vindex] = {ip = ip, violation = sqli_violation_type}
                vindex = vindex + 1
            end
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
end

-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla Security Consecutive Request Set Frequency

For events matching the message matcher, identify scenarios where the same set of request paths
are being requested in the same order, and generate violation notices/TSV output for clients that
exceed set_threshold consecutive occurrences within the timer interval.

The acceptable_variance configuration parameter can be used to specify the upper bounds on the
number of unique paths that will be tracked. If a client makes requests to >= this number of
unique paths, the client is considered varied enough and is no longer tracked during this
interval.

## Sample Configuration
```lua
filename = "moz_security_pathsetfreq.lua"
message_matcher = "Logger == 'input.nginx'"
ticker_interval = 60
preserve_data = false

id_field = "Fields[remote_addr]" -- field to use as the identifier
-- id_field_capture = ",? *([^,]+)$",  -- optional e.g. extract the last entry in a comma delimited list
request_field = "Fields[request] -- field containing HTTP request
-- request_field_capture = "%S+%s+(%S+)" -- optional, e.g., extract second string in field

-- send_iprepd = false -- optional, if true plugin will generate iprepd violation messages
-- violation_type = "fxa:client_pathsetfreq" -- required in violations mode, iprepd violation type
set_threshold = 50 -- consecutive repeats to generate violation/tsv output
acceptable_variance = 5 -- >= unique request paths to ignore client for interval
-- no_single_set = true -- if true, disable tracking set with single path (e.g., repeated)
```
--]]

require "string"
require "table"

local uri = require "lpeg.uri"

local id_field          = read_config("id_field") or error("id_field must be configured")
local id_fieldc         = read_config("id_field_capture")
local request_field     = read_config("request_field") or error("request_field must be configured")
local request_fieldc    = read_config("request_field_capture")
local set_threshold     = read_config("set_threshold") or error("set_threshold must be configured")
local accept_variance   = read_config("acceptable_variance") or error("acceptable_variance must be configured")
local no_single         = read_config("no_single_set")

local tbsend
local violation_type
local send_iprepd = read_config("send_iprepd")
if send_iprepd then
    tbsend = require "heka.iprepd".send
    violation_type = read_config("violation_type") or error("violation_type must be configured")
end

local list = {}

function process_message()
    local id = read_message(id_field)
    if not id then return -1, "no id_field" end
    if id_fieldc then
        id = string.match(id, id_fieldc)
        if not id then return 0 end -- no error as the capture may intentionally reject entries
    end
    local req = read_message(request_field)
    if not req then return -1, "no request_field" end
    if request_fieldc then
        req = string.match(req, request_fieldc)
        if not req then return 0 end -- no error as the capture may intentionally reject entries
    end

    local m = uri.uri_reference:match(req)
    if not m or not m.path then return 0 end

    local w = list[id]
    if not w then
        list[id] = {
            paths   = { m.path },   -- path set list
            r       = 0,            -- consecutive occurrences in stream
            varied  = false,        -- true if acceptable variance
            estab   = false,        -- true if set established
            setptr  = 0             -- index into path list for established entry
        }
        return 0
    end

    if w.varied then return 0 end -- acceptable variance, ignore for remainder of interval

    local pathsetlen = #w.paths
    local foundi = 0
    for i,v in ipairs(w.paths) do
        if v == m.path then
            foundi = i
            break
        end
    end

    if not w.estab then
        if foundi == 0 then -- path isn't known
            if pathsetlen + 1 >= accept_variance then -- addition meets variance requirement
                w.varied = true
                w.paths = nil -- no longer needs paths, nil now for gc
            else
                w.paths[pathsetlen + 1] = m.path
                pathsetlen = pathsetlen + 1
            end
        else
            -- found, establish if index 1
            if foundi == 1 and not (no_single and pathsetlen == 1) then
                w.estab = true
                w.r = 1
                if pathsetlen > 1 then
                    w.setptr = 2
                else
                    w.setptr = 1
                    w.r = 2
                end
            else
                if foundi ~= pathsetlen then -- collapse repeats of secondary set members
                    w.varied = true -- divergence from tracked set
                    w.paths = nil
                end
            end
        end
    else
        if w.paths[w.setptr] == m.path then
            w.setptr = w.setptr + 1
            if w.setptr > pathsetlen then
                w.r = w.r + 1
                w.setptr = 1
            end
        else
            local tsp = w.setptr
            if tsp == 1 then
                tsp = pathsetlen
            else
                tsp = w.setptr - 1
            end
            if w.paths[tsp] ~= m.path then
                w.varied = true -- divergence from tracked set
                w.paths = nil
            end
        end
    end

    return 0
end

function timer_event(ns)
    local slist = {}
    for k,v in pairs(list) do
        if v.r >= set_threshold and v.estab and not v.varied then
            table.insert(slist, k)
        end
    end
    table.sort(slist)

    local violations = {}
    for i,ip in ipairs(slist) do
        local cnt = list[ip].r
        if not send_iprepd then
            add_to_payload(ip, "\t", cnt, "\n")
        else
            violations[i] = {ip = ip, violation = violation_type}
        end
    end

    if not send_iprepd then
        inject_payload("tsv", "statistics")
    else
        tbsend(violations)
    end

    list = {}
end

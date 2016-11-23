-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
#  Mozilla Shield Study Enrollemnt

## Sample Configuration
```lua
filename = 'shield_study_enrollment.lua'
message_matcher = 'Type == "telemetry" && Fields[docType] == "shield-study"'
ticker_interval = 60
preserve_data = true
```
--]]

_PRESERVATION_VERSION = 0

require "cjson"
require "math"
require "os"
require "string"
require "table"

reports = {}
cday_t = 0

function process_message()
    local json = read_message("Fields[submission]")
    local ok, doc = pcall(cjson.decode, json)
    if not ok then
        return -1, doc
    end

    local p = doc.payload
    if type(p) ~= "table" then return -1, "payload is not a table" end

    local day_t = math.floor(read_message("Timestamp") / 86400e9) * 86400
    if day_t > cday_t then cday_t = day_t end

    local day = reports[day_t]
    if not day then
        if day_t < cday_t then 
            -- don't go backwards as this report may have already been finalized
            return -1, string.format("dropped data for %s", os.date("%Y-%m-%d", day_t))
        end
        day = {}
        reports[day_t] = day
    end

    local sn = tostring(p.study_name or "UNKNOWN")
    local study = day[sn]
    if not study then
        study = {}
        day[sn] = study
    end

    local ss = tostring(p.study_state or "UNKNOWN")
    local state = study[ss]
    if not state then
        state = {}
        study[ss] = state
    end

    local bn = tostring(p.branch or "UNKNOWN")
    local branch = state[bn]
    if not branch then
        branch = {}
        state[bn] = branch
    end

    local nc = tostring(read_message("Fields[normalizedChannel]") or "UNKNOWN")
    local cnt = branch[nc]
    if not cnt then
        branch[nc] = 1
    else 
        branch[nc] = cnt + 1
    end
    return 0
end

local msg = {
    Type = "report.daily",
    EnvVersion = tostring(_PRESERVATION_VERSION),
    Fields = {
        day     = "", -- YYYY-MM-DD
        name    = "count",
        ext     = "tsv", 
        data    = "",
    }
}

function timer_event(ns, shutdown)
    for day_t, day in pairs(reports) do
        local ds = os.date("%Y-%m-%d", day_t)
        local dr = {}
        local dr_cnt = 1
        dr[dr_cnt] = "day\tstudy_name\tstudy_state\tbranch\tchannel\tcount"
        for sn, study in pairs(day) do
            for ss, state in pairs(study) do
                for bn, branch in pairs(state) do
                    for nc, cnt in pairs(branch) do
                        dr_cnt = dr_cnt + 1
                        dr[dr_cnt] = string.format("%s\t%s\t%s\t%s\t%s\t%d", ds, sn, ss, bn, nc, cnt)
                    end                    
                end
            end
        end
        msg.Fields.day = ds
        msg.Fields.data = table.concat(dr, "\n")
        inject_message(msg)
        if day_t < cday_t then reports[day_t] = nil end
    end
end

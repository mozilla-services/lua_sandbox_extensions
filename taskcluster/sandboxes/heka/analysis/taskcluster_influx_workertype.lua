-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Taskcluster InfluxDB workertype task metrics

## Sample Configuration
```lua
filename        = 'taskcluster_influx_workertype.lua'
message_matcher = "Type == 'influx'"
ticker_interval = 60
memory_limit    = 20e6
output_limit    = 8e6
preserve_data   = true

process_message_inject_limit = 1

environment                 = "dev"
cuckoo_filter_items         = 100000 -- default
cuckoo_filter_interval_size = 1      -- default
preservation_version        = 0
```
--]]
require "cjson"
require "cuckoo_filter_expire"
require "os"
require "string"
require "table"


cf   = cuckoo_filter_expire.new(read_config("cuckoo_filter_items") or 100000,
                                read_config("cuckoo_filter_interval_size") or 1)
data = {}
data_time_m = 0

local environment = read_config("environment") or "dev"
--[[ {
workerType = {
    time_m = 0 -- time of the most recent row
    rows = {
        time_m = [modified,defined,pending,running,completed,failed,exception,concurrent]
    }
}
--]]

local function find_row(wt, time_m)
    if os.time() - time_m <= -60  -- protect against times in the future
    or data_time_m - time_m >= 3600 then -- ignore data before the analysis window
        return
    end
    if time_m > data_time_m then data_time_m = time_m end

    local w = data[wt]
    local row
    if not w then
        row = {true,0,0,0,0,0,0,0}
        w = {time_m = time_m, rows = {[time_m] = row}}
        data[wt] = w
        return w, row
    end

    if time_m > w.time_m then -- fill in any missing buckets
        local c = w.rows[w.time_m][8]
        for i=w.time_m + 60, time_m, 60 do
            row = {true,0,0,0,0,0,0,c}
            w.rows[i] = row
        end
        w.time_m = time_m
        return w, row
    end
    return w, w.rows[time_m]
end


local function adjust_concurrency(w, time_m, delta)
    for i=time_m, w.time_m, 60 do
        local row = w.rows[i]
        row[1] = true
        local c = row[8] + delta
        if c < 0 then c = 0 end
        row[8] = c
    end
end


local function is_dupe(ns, taskid, runid, state)
    local rv = cf:add(taskid .. tostring(runid) .. state, ns)
    return not rv
end


local function normalize_workertype(wt)
    if wt:match("^test%-.+%-a$") then
        wt = "test-generic"
    elseif wt:match("^dummy%-worker%-") then
        wt = "dummy-worker"
    elseif wt:match("^dummy%-type%-") then
        wt = "dummy-type"
    end
    return wt
end


local function get_time_m(ts)
    if not ts then return nil end
    local time_m
    local t = {}
    t.year, t.month, t.day, t.hour, t.min, t.sec = ts:match("^(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)")
    if t.year then
        time_m = os.time(t)
        time_m = time_m - (time_m % 60)
    end
    return time_m
end


local function update_stats(ns, runid, state, j)
    local wt = normalize_workertype(j.status.workerType or "_")
    if not runid then
        local time_m = ns / 1e9
        time_m = time_m - (time_m % 60)
        local w, row = find_row(wt, time_m)
        if row then
            row[1] = true
            row[2] = row[2] + 1
        end
    elseif state == "pending" then
        local time_m = get_time_m(j.status.runs[runid + 1].scheduled)
        local w, row = find_row(wt, time_m)
        if row then
            row[1] = true
            row[3] = row[3] + 1
        end
    elseif state == "running" then
        local time_m = get_time_m(j.status.runs[runid + 1].started)
        local w, row = find_row(wt, time_m)
        if row then
            row[1] = true
            row[4] = row[4] + 1
            adjust_concurrency(w, time_m, 1)
        end
    elseif state == "completed" then
        local time_m = get_time_m(j.status.runs[runid + 1].resolved)
        local w, row = find_row(wt, time_m)
        if row then
            row[1] = true
            row[5] = row[5] + 1
            adjust_concurrency(w, time_m, -1)
        end
    elseif state == "failed" then
        local time_m = get_time_m(j.status.runs[runid + 1].resolved)
        local w, row = find_row(wt, time_m)
        if row then
            row[1] = true
            row[6] = row[6] + 1
            adjust_concurrency(w, time_m, -1)
        end
    elseif state == "exception" then
        local time_m = get_time_m(j.status.runs[runid + 1].resolved)
        local w, row = find_row(wt, time_m)
        if row then
            row[1] = true
            row[7] = row[7] + 1
            if j.status.runs[runid + 1].started then
                adjust_concurrency(w, time_m, -1)
            end
        end
    end
end

local last_flush = nil
function process_message()
    local ok, j = pcall(cjson.decode, read_message("Payload"))
    if not ok then return -1, j end

    local runid = j.runId
    local state = j.status.state
    local ns    = read_message("Timestamp")
    if is_dupe(ns, j.status.taskId, runid, state) then return 0 end

    update_stats(ns, runid, state, j)

    -- during a backfill limit the output size to the expected max
    if not last_flush then
        last_flush = data_time_m
    elseif data_time_m - last_flush >= 3600 then
        timer_event()
    end

    return 0
end


function timer_event()
    local stats = {}
    local stats_cnt = 0
    for wt, w in pairs(data) do
        if w.time_m < data_time_m and w.rows[w.time_m][8] > 0 then
            find_row(wt, data_time_m) -- advance the buffer
        end
        for time_m, row in pairs(w.rows) do
            if row[1] then
                stats_cnt = stats_cnt + 1
                stats[stats_cnt] = string.format(
                    "taskcluster_workertype_tasks,workertype=%s,environment=%s defined=%d,pending=%d,running=%d,completed=%d,failed=%d,exception=%d,concurrent=%d %d",
                    wt, environment, row[2], row[3], row[4], row[5], row[6], row[7], row[8], time_m * 1e9)
                row[1] = false
            end
            if data_time_m - time_m >= 3600 then
                w.rows[time_m] = nil
                if w.time_m == time_m then -- if the most current row expires, remove the workerType
                    data[wt] = nil
                    break
                end
            end
        end
    end
    if stats_cnt > 0 then
        inject_message({Payload = table.concat(stats, "\n")})
    end
    last_flush = data_time_m
end

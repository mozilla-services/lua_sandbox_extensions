-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Taskcluster InfluxDB workertype lag metrics

## Sample Configuration
```lua
filename        = 'taskcluster_influx_workertype_lag.lua'
message_matcher = "Type == 'influx' && Logger == 'input.tc_task_running'"
ticker_interval = 60
memory_limit    = 20e6
output_limit    = 8e6
instruction_limit = 10e6
preserve_data   = true

preservation_version        = 0
environment                 = "dev"
samples                     = 1000 -- rolling window of X samples to compare against the historical values
samples_quantile            = 0.90 -- 0.01 - 0.99

```
--]]
_PRESERVATION_VERSION = read_config("preservation_version") or 0

require "cjson"
require "math"
require "os"
require "string"
require "table"
local p2    = require "streaming_algorithms.p2"
local util  = require "taskcluster.util"

data = {}
data_time_m = 0

local environment = read_config("environment") or "dev"
local samples     = read_config("samples") or 1000
local samples_q   = read_config("samples_quantile") or 0.90
samples_q = math.floor(samples_q * 100) / 100
assert(samples_q > 0 and samples_q < 1)
local label_q     = string.format("sp%d", samples_q * 100)

local function find_wt(wt)
    local w = data[wt]
    if not w then
        w = {
            updated = data_time_m,
            p999 = p2.quantile(0.999),
            p99  = p2.quantile(0.99),
            p90  = p2.quantile(0.90),
            samples_idx = 1,
            samples = {}
        }
        data[wt] = w
    end
    return w
end


function process_message()
    local ok, j = pcall(cjson.decode, read_message("Payload"))
    if not ok then return -1, j end
    if not j.runId or j.status.state ~= "running" then return 0 end

    local run               = j.status.runs[j.runId + 1]
    local time_m, started   = util.get_time_m(run.started)
    local scheduled         = util.get_time_t(run.scheduled)
    local lag               = started - scheduled
    if time_m > data_time_m then data_time_m = time_m end

    local w   = find_wt(util.normalize_workertype(j.status.workerType))
    w.updated = data_time_m
    local idx = w.samples_idx
    w.samples[idx] = lag
    w.p999:add(lag) -- p50 technically 0.4995 is pulled out of marker 1
    w.p99:add(lag)
    w.p90:add(lag)

    idx = idx + 1
    if idx > samples then idx = 1 end
    w.samples_idx = idx
    return 0
end


local sq = p2.quantile(samples_q)
function timer_event()
    local stats = {}
    local stats_cnt = 0
    for wt, w in pairs(data) do
        local p999 = w.p999
        local count = p999:count(4)
        if count > 4 then
            sq:clear()
            for i=1, samples do
                local v = w.samples[i]
                if not v then break end
                sq:add(v)
            end
            local sqe = sq:estimate(2)
            if sqe ~= sqe then sqe = 0 end -- NaN set to zero
            stats_cnt = stats_cnt + 1
            stats[stats_cnt] = string.format(
                "taskcluster_workertype_lag,workertype=%s,environment=%s count=%d,p50=%d,p90=%d,p99=%d,p999=%d,%s=%d %d",
                wt, environment, count, p999:estimate(1), w.p90:estimate(2), w.p99:estimate(2), p999:estimate(2),
                label_q, sqe, data_time_m * 1e9)
        end
        if data_time_m - w.updated >= 86400 * 7 then data[wt] = nil end -- prune anything that has been inactive for a week
    end
    if stats_cnt > 0 then
        inject_message({Payload = table.concat(stats, "\n")})
    end
end

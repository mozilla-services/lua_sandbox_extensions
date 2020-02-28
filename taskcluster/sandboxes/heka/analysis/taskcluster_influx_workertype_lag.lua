-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Taskcluster InfluxDB workertype lag metrics

## Sample Configuration
```lua
filename        = 'taskcluster_influx_workertype_lag.lua'

message_matcher = "Type == 'timing' && Fields[level] == 0 && Fields[started] != NIL && Logger =~ '^input.tc_task'"
ticker_interval = 60
memory_limit    = 20e6
output_limit    = 8e6
instruction_limit = 10e6
preserve_data   = true

preservation_version        = 0
environment                 = "dev"
cluster                     = "firefox"
samples                     = 100 -- rolling window of X samples to compare against the historical values
samples_quantile            = 0.90 -- 0.01 - 0.99

```
--]]
_PRESERVATION_VERSION = (read_config("preservation_version") or 0) + 2

require "cjson"
require "math"
require "os"
require "string"
require "table"
local p2    = require "streaming_algorithms.p2"
local util  = require "taskcluster.util"

data = {}
data_time_m = 0

local cluster     = read_config("cluster") or error "cluster must be set"
local environment = read_config("environment") or "dev"
local samples     = read_config("samples") or 100
local samples_q   = read_config("samples_quantile") or 0.90
samples_q = math.floor(samples_q * 100) / 100
assert(samples_q >= 0.01 and samples_q <= 0.99)
local label_q     = string.format("p%d", samples_q * 100)

local function find_wt(wt, pri)
    local w = data[wt]
    if not w then
        w = {}
        data[wt] = w
    end
    w = w[pri]
    if not w then
        w = {
            updated = data_time_m,
            q  = p2.quantile(samples_q), -- historical quantile
            samples_idx = 1,
            samples = {}
        }
        data[wt][pri] = w
    end
    return w
end


function process_message()
    local time_m, started   = util.get_time_m(read_message("Fields[started]"))
    local scheduled         = util.get_time_t(read_message("Fields[scheduled]"))
    local lag               = started - scheduled
    if time_m > data_time_m then data_time_m = time_m end

    local pid = read_message("Fields[provisionerId]") or "null"
    local wt = pid .. "/" .. util.normalize_workertype(read_message("Fields[workerType]"))
    local pri = read_message("Fields[priority]") or "very-low"
    local w   = find_wt(wt, pri)
    w.updated = data_time_m
    local idx = w.samples_idx
    w.samples[idx] = lag
    w.q:add(lag)

    idx = idx + 1
    if idx > samples then idx = 1 end
    w.samples_idx = idx
    return 0
end


local sq = p2.quantile(samples_q)
function timer_event()
    local stats = {}
    local stats_cnt = 0
    for wt, t in pairs(data) do
        local items = 0
        for pri, w in pairs(t) do
            items = items + 1
            local q = w.q
            local count = q:count(4)
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
                    "taskcluster_workertype_lag,workertype=%s,environment=%s,cluster=%s,priority=%s count=%d,h%s=%d,s%s=%d %d",
                    wt, environment, cluster, pri, count, label_q, q:estimate(2), label_q, sqe, data_time_m * 1e9)
            end
            if data_time_m - w.updated >= 86400 * 7 then data[wt][pri] = nil end -- prune anything that has been inactive for a week
        end
        if items == 0 then data[wt] = nil end
    end
    if stats_cnt > 0 then
        inject_message({Payload = table.concat(stats, "\n")})
    end
end

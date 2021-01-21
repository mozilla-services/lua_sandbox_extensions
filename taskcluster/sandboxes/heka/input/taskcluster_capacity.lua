-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.


--[[
# taskcluster_capacity - Pull in ci-configuration and load the workerpool capacity values into BigQuery

## Sample Configuration
```lua
filename            = 'workerpool_capacity.lua'
ticker_interval     = 3600 -- only performs the load an hour into the next day
instruction_limit   = 0

-- directory location to store the intermediate output files
batch_dir           = "/var/tmp" -- default
bq_dataset          = "taskclusteretl" -- default
bq_table            = "workerpool_capacity" -- default

alert = {
  disabled = false,
  prefix = true,
  throttle = 86400,
  modules = {
    email = {recipients = {"notify@example.com"}},
  },
}

```
--]]

require "cjson"
require "io"
require "math"
require "os"
require "string"
require "table"
local lyaml = require "lyaml"
local alert  = require "heka.alert"

local batch_dir     = read_config("batch_dir") or "/var/tmp"
local bq_dataset    = read_config("bq_dataset") or "taskclusteretl"
local bq_table      = read_config("bq_table") or "workerpool_capacity"
local config_file   = string.format("%s/%s.tmp", batch_dir, read_config("Logger"))

local function get_config()
    local config_url = "https://hg.mozilla.org/ci/ci-configuration/raw-file/tip/worker-pools.yml"
    local cmd        = string.format("rm -f %s;curl -L -s --compressed -f --retry 2 -m 60 --max-filesize 1000000 %s -o %s",
                                     config_file, config_url, config_file)

    local rv = os.execute(cmd)
    if rv ~= 0 then
        return nil, string.format("curl error: %d", rv/256)
    end

    local fh = io.open(config_file, "rb")
    if not fh then
        return nil, "file open failed (read)"
    end

    local ystr = fh:read("*a")
    fh:close()
    local ok, y = pcall(lyaml.load, ystr)
    if not ok then
        return nil, string.format("parse failed: %n", y)
    end

    return y
end


local function process_config(y, time_t)
    local dstr = os.date("%Y-%m-%d", time_t)
    local entries = {}
    for i,v in ipairs(y.pools) do
        -- 'static' providers do not contain instance_types configuration
        if v.provider_id ~= "static" then
            local pid, wt = string.match(v.pool_id, "([^/]+)/(.+)")
            for m,n in ipairs(v.config.instance_types) do
                local cap = n.capacityPerInstance or 1
                if cap > 1 then
                    if pid == "{pool-group}" then
                        for o,p in ipairs(v.variants) do
                            entries[#entries + 1] = {date = dstr, provisionerId = p["pool-group"], workerType = wt, providerId = v.provider_id, capacity = cap, instanceType = n.instanceType or n.machine_type}
                        end
                    else
                        entries[#entries + 1] = {date = dstr, provisionerId = pid, workerType = wt, providerId = v.provider_id, capacity = cap, instanceType = n.instanceType or n.machine_type}
                    end
                end
            end
        end
    end
    return entries
end


local function output(wpc)
    local fh = assert(io.open(config_file, "wb"))
    if not fh then
        return "file open failed (write)"
    end

    for i,v in ipairs(wpc) do
        fh:write(cjson.encode(v), "\n")
    end
    fh:close()

    local bq_cmd = string.format("bq load --source_format NEWLINE_DELIMITED_JSON --ignore_unknown_values %s.%s %s",
                                 bq_dataset, bq_table, config_file)
    local rv = os.execute(bq_cmd)
    if rv ~= 0 then
        return string.format("bq error: %d", rv/256)
    end
end


local function get_start_of_day(time_t)
    return time_t - (time_t % 86400)
end


local alert_tmpl = [[The last successful worker-pools.yml load occured on %s.
The missing data will cause the cost per time calculations to be off for some
workerPoolIds, greatly skewing the cost per task results. If the yml file
hasn't changed the missing data can be duplicated from the last day in the
table. The load is retried hourly so if you are seeing this message there is a
bigger problem (schema incompatibility, the plugin was not running, network or
end point issues)
]]

function process_message(checkpoint)
    local sod = get_start_of_day(os.time())
    if sod == checkpoint then return 0 end

    if checkpoint and sod - checkpoint > 86400 then
        alert.send(read_config("Logger"), "load", string.format(alert_tmpl, os.date("%Y-%m-%d", checkpoint)))
    end

    local cfg, err = get_config()
    if not cfg then return -1, err end

    local ok, wpc = pcall(process_config, cfg, sod)
    if ok then
        err = output(wpc)
        if not err then
            inject_message(nil, sod)
        else
            return -1, err
        end
    else
        alert.send(read_config("Logger"), "process_config", wpc)
        return -1, wpc
    end
    return 0
end

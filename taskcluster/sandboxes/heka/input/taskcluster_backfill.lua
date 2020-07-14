-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Taskcluster Backfill

## Sample Configuration
```lua
filename            = 'taskcluster_backfill.lua'
ticker_interval     = 3600 -- won't perform a backfill until at least an hour into the next day
instruction_limit   = 0

decoders_taskcluster_live_backing_log = {
    -- taskcluster_schema_path = "/usr/share/luasandbox/schemas/taskcluster" -- default
    -- base_taskcluster_url = "https://firefox-ci-tc.services.mozilla.com/api/queue/v1" -- default
}


```
--]]
require "cjson"
require "os"
require "string"
local dm = require "decoders.taskcluster.live_backing_log"

local function get_start_of_day(time_t)
    return time_t - (time_t % 86400)
end

local td_day    = get_start_of_day(os.time())
local log_day   = td_day
local br_day    = br_day
local fn        = string.format("/var/tmp/%s.json", read_config("Logger"))

local function error_query(cmd, st, et, decode)
    print("cmd", cmd)
    local rv = os.execute(cmd)
    if rv ~= 0 then
        pcall(inject_message, {
            Type    = "error.execute.taskcluster_backfill",
            Payload = tostring(rv/256),
            Fields  = {detail = cmd}})
        return st
    end

    local fh = io.open(fn, "rb")
    if fh then
        local ok
        local j = fh:read("*a")
        fh:close()
        ok, j = pcall(cjson.decode, j)
        if ok then
            for i, row in ipairs(j) do
                local ok, err = pcall(decode, row.data)
                if not ok or err then
                    pcall(inject_message, {
                        Type    = row.type .. ".backfill",
                        Payload = err,
                        Fields  = {
                            taskId = row.taskId,
                            data = row.data}})
                end
            end
        else
            pcall(inject_message, {
                Type    = "error.query.taskcluster_backfill",
                Payload = j,
                Fields  = {detail = cmd}})
        end
        return get_start_of_day(et)
    else
        pcall(inject_message, {
            Type    = "error.open.taskcluster_backfill",
            Payload = "file not found",
            Fields  = {detail = cmd}})
    end
    return st
end


local function get_date(time_t)
    return os.date("%Y-%m-%d", time_t)
end


function process_message(checkpoint)
    if checkpoint then
        local td, log, br = string.match(checkpoint, "^(%d+)\t(%d+)\t?(%d*)$")
        td_day = tonumber(td) or td_day
        log_day = tonumber(log) or log_day
        br_day = tonumber(br) or br_day
    end

    local time_t = os.time()
    if time_t - td_day >= 86400 + 3600 then
        local cmd = string.format('rm -f %s;bq query --nouse_legacy_sql --format json \'select taskId, type, data from taskclusteretl.error where data is not NULL and type like "error.%%.task_definition" and time >= "%s" and time < "%s"\' > %s',
                                  fn, get_date(td_day), get_date(time_t), fn)
        td_day = error_query(cmd, td_day, time_t, dm.decode_task_definition_error)
    end

    if time_t - log_day >= 86400 + 3600 then
        local cmd = string.format('rm -f %s;bq query --nouse_legacy_sql --format json \'select taskId, type, data from taskclusteretl.error where data is not NULL and type like "error.%%.log" and time >= "%s" and time < "%s"\' > %s',
                                  fn, get_date(log_day), get_date(time_t), fn)
        log_day = error_query(cmd, log_day, time_t, dm.decode_log_error)
    end

    if time_t - br_day >= 86400 + 3600 then
        local cmd = string.format('rm -f %s;bq query --nouse_legacy_sql --format json \'select taskId, type, data from taskclusteretl.error where data is not NULL and type like "error.%%.build_resource" and time >= "%s" and time < "%s"\' > %s',
                                  fn, get_date(log_day), get_date(time_t), fn)
        br_day = error_query(cmd, br_day, time_t, dm.decode_build_resource_error)
    end

    inject_message(nil, string.format("%d\t%d\t%d", td_day, log_day, br_day))
    return 0
end

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
integration_test    = false

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
local integration_test = read_config("integration_test")

local function get_start_of_day(time_t)
    return time_t - (time_t % 86400)
end


local fn = string.format("/var/tmp/%s_query.json", read_config("Logger"))


local function get_decoder(typ)
    local name = typ:match("error%.curl%.(.+)") or ""
    name = string.format("decode_%s_error", name)
    return dm[name] or function() return end
end


local function error_query(cmd, st, et)
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
                local decode = get_decoder(row.type)
                local ok, err = pcall(decode, row.data)
                if not ok or err then
                    pcall(inject_message, {
                        Type    = row.type .. ".backfill",
                        Payload = err,
                        Fields  = {
                            taskId = row.taskId}})
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
    local time_t = os.time()
    checkpoint = checkpoint or get_start_of_day(time_t)

    if time_t - checkpoint >= 86400 + 3600 then
        local cmd = string.format('rm -f %s;bq query --nouse_legacy_sql --format json \'select taskId, type, data from taskclusteretl.error where data is not NULL and type like "error.curl.%%" and time >= "%s" and time < "%s"\' > %s',
                                  fn, get_date(checkpoint), get_date(time_t), fn)
        checkpoint = error_query(cmd, checkpoint, time_t)
    end

    inject_message(nil, checkpoint)
    return 0
end

if integration_test then
    os.execute("rm -f " .. fn)
    process_message = function()
        for i = 1,10 do
            os.execute("sleep 1")
            local fh = io.open(fn, "rb")
            if fh then
                fh:close()
                break
            end
        end
        local time_t = os.time()
        local checkpoint = error_query("echo starting", 0, time_t)
        assert(rv ~= checkpoint, "checkpoint was not advanced")
        return 0
    end
end

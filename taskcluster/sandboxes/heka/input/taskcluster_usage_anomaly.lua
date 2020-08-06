-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Taskcluster Usage Anomaly Monitor

Compares the most recent day's utilization to the previous week's. With a
minimum threshold in standard deviations and hours to reduce the noise.

Current Dimension Checks
1) workerPoolId
2) project (project/kind/platform/collection/suite)

## Sample Configuration
```lua
filename            = 'taskcluster_usage_anomaly.lua'
ticker_interval     = 3600 -- poll every hour but the query will only trigger
                           -- once a day after the derived_task_summary is
                           -- populated

alert = {
  disabled = false,
  prefix   = true,
  modules  = {
    email = {recipients = { "example@example.com" } },
  },
}

```
--]]
require "cjson"
require "io"
require "os"
require "string"
local alert  = require "heka.alert"

local function get_start_of_day(time_t)
    return time_t - (time_t % 86400)
end

local fn = string.format("/var/tmp/%s_query.json", read_config("Logger"))
local qfn = string.format("/var/tmp/%s_query.sql", read_config("Logger"))

local sql = [[
DECLARE
  start_date DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 8 day);
DECLARE
  end_date DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 1 day);
WITH
  hist AS (
  SELECT
    date,
    project,
    kind,
    platform,
    collection,
    suite,
    SUM(UNIX_SECONDS(resolved) - UNIX_SECONDS(started)) / 3600 AS hours
  FROM
    taskclusteretl.derived_task_summary
  WHERE
    date >= start_date
    AND date <= end_date
  GROUP BY
    date,
    project,
    kind,
    platform,
    collection,
    suite),
  resid AS (
  SELECT
    project,
    kind,
    platform,
    collection,
    suite,
    SUM(hours) AS hours,
    AVG(hours) AS avg,
    stddev_pop(hours) AS sd
  FROM
    hist
  WHERE
    date != end_date
  GROUP BY
    project,
    kind,
    platform,
    collection,
    suite),
  sd AS (
  SELECT
    resid.project,
    resid.kind,
    resid.platform,
    resid.collection,
    resid.suite,
    resid.avg AS avg_hours,
    hist.hours AS current_hours,
    hist.hours - resid.avg AS delta,
    sd,
    (hist.hours - resid.avg) / sd AS num_sd
  FROM
    hist
  RIGHT JOIN
    resid
  ON
    (hist.project IS NULL
      AND resid.project IS NULL
      OR hist.project = resid.project)
    AND (hist.kind IS NULL
      AND resid.kind IS NULL
      OR hist.kind = resid.kind)
    AND (hist.platform IS NULL
      AND resid.platform IS NULL
      OR hist.platform = resid.platform)
    AND (hist.collection IS NULL
      AND resid.collection IS NULL
      OR hist.collection = resid.collection)
    AND (hist.suite IS NULL
      AND resid.suite IS NULL
      OR hist.suite = resid.suite)
  WHERE
    hist.date = end_date
    AND sd != 0 ),
  hist_wp AS (
  SELECT
    date,
    provisionerId,
    workerType,
    SUM(UNIX_SECONDS(resolved) - UNIX_SECONDS(started)) / 3600 AS hours
  FROM
    taskclusteretl.derived_task_summary
  WHERE
    date >= start_date
    AND date <= end_date
  GROUP BY
    date,
    provisionerId,
    workerType ),
  resid_wp AS (
  SELECT
    provisionerId,
    workerType,
    SUM(hours) AS hours,
    AVG(hours) AS avg,
    stddev_pop(hours) AS sd
  FROM
    hist_wp
  WHERE
    date != end_date
  GROUP BY
    provisionerId,
    workerType),
  sd_wp AS (
  SELECT
    resid_wp.provisionerid,
    resid_wp.workertype,
    resid_wp.avg AS avg_hours,
    hist_wp.hours AS current_hours,
    hist_wp.hours - resid_wp.avg AS delta,
    sd,
    (hist_wp.hours - resid_wp.avg) / sd AS num_sd
  FROM
    hist_wp
  RIGHT JOIN
    resid_wp
  ON
    (hist_wp.provisionerid IS NULL
      AND resid_wp.provisionerid IS NULL
      OR hist_wp.provisionerid = resid_wp.provisionerid)
    AND (hist_wp.workertype IS NULL
      AND resid_wp.workertype IS NULL
      OR hist_wp.workertype = resid_wp.workertype)
  WHERE
    hist_wp.date = end_date
    AND sd != 0 )
SELECT
  end_date AS date,
  "project" AS type,
  CONCAT(ifnull(project,
      "null"), "/", ifnull(kind,
      "null"), "/", ifnull(platform,
      "null"), "/", ifnull(collection,
      "null"), "/", ifnull(suite,
      "null")) AS dimensions,
  sd.sd AS historical_sd,
  avg_hours AS historical_avg_hours,
  current_hours,
  num_sd
FROM
  sd
WHERE
  num_sd >= 3
  AND delta > 1000
UNION ALL
SELECT
  end_date AS date,
  "workerPoolId" AS type,
  CONCAT(ifnull(provisionerId,
      "null"), "/", ifnull(workerType,
      "null")) AS dimensions,
  sd,
  avg_hours,
  current_hours,
  num_sd
FROM
  sd_wp
WHERE
  num_sd >= 3
  AND delta > 1000
]]

local fh = assert(io.open(qfn, "wb"))
fh:write(sql)
fh:close()
fh = nil


local function usage_query(cmd, st, et)
    print("cmd", cmd)
    local rv = os.execute(cmd)
    if rv ~= 0 then
        pcall(inject_message, {
            Type    = "error.execute.taskcluster_usage_anomaly",
            Payload = tostring(rv/256),
            Fields  = {detail = cmd}})
        return st
    end

    local fh = io.open(fn, "rb")
    if fh then
        local json = fh:read("*a")
        fh:close()
        local ok, j = pcall(cjson.decode, json)
        if ok then
            if #j > 0 then -- and empty result set is returned as "[[]]"
                if j[1].date then
                    alert.send(read_config("Logger"), "usage anomaly", json)
                end
            end
        else
            pcall(inject_message, {
                Type    = "error.query.taskcluster_usage_anomaly",
                Payload = j,
                Fields  = {detail = cmd}})
        end
        return get_start_of_day(et)
    else
        pcall(inject_message, {
            Type    = "error.open.taskcluster_usage_anomaly",
            Payload = "file not found",
            Fields  = {detail = cmd}})
    end
    return st
end


function process_message(checkpoint)
    local time_t = os.time()
    checkpoint = checkpoint or get_start_of_day(time_t)

    if time_t - checkpoint >= 86400 + (3600 * 8) then
        local cmd = string.format("rm -f %s;bq query --nouse_legacy_sql --format prettyjson --flagfile %s > %s", fn, qfn, fn)
        checkpoint = usage_query(cmd, checkpoint, time_t)
    end

    inject_message(nil, checkpoint)
    return 0
end

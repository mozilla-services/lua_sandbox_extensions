
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Taskcluster - Pull in Treeherder data useful in BigQuery analysis

## Sample Configuration
```lua
filename            = 'taskcluster_treeherder.lua'
ticker_interval     = 3600 -- only performs the load an hour into the next day
instruction_limit   = 0

-- directory location to store the intermediate output files
batch_dir           = "/var/tmp" -- default
bq_dataset          = "taskclusteretl"
bq_alert_table      = "perfherder_alert"
bq_commit_table     = "commit_log"

db          = "treeherder"
db_host     = "treeherder-prod-ro.cd3i3txkp6c6.us-east-1.rds.amazonaws.com"
db_user     = "user"
_db_pass    = "password"

alert = {
  disabled = false,
  prefix = true,
  throttle = 0,
  modules = {
    email = {recipients = {"notify@example.com"}},
  },
}
```
--]]
require "cjson"
require "io"
require "os"
require "string"
local driver = require "luasql.mysql"
local alert  = require "heka.alert"

local batch_dir         = read_config("batch_dir") or "/var/tmp"
local bq_dataset        = read_config("bq_dataset") or error"must specify bq_dataset"
local bq_alert_table    = read_config("bq_alert_table") or error"must specify bq_alert_table"
local bq_commit_table   = read_config("bq_commit_table") or error"must specify bq_commit_table"
local db                = read_config("db") or "treeherder"
local db_host           = read_config("db_host") or "treeherder-prod-ro.cd3i3txkp6c6.us-east-1.rds.amazonaws.com"
local db_user           = read_config("db_user") or error"must specify db_user"
local db_pass           = read_config("_db_pass") or error"must specify _db_pass"
local db_port           = read_config("db_port") or 3306

local function get_start_of_day(time_t)
    return time_t - (time_t % 86400)
end

local function get_date(time_t)
    return os.date("%Y-%m-%d", time_t)
end

local alert_day     = get_start_of_day(os.time())
local commit_day    = alert_day
local env           = assert(driver.mysql())

local alert_query_tmpl = [[
SELECT alert.id,
       alert.is_regression,
       CASE summary.status
           WHEN 0 THEN 'untriaged'
           WHEN 1 THEN 'downstream'
           WHEN 2 THEN 'reassigned'
           WHEN 3 THEN 'invalid'
           WHEN 4 THEN 'improvement'
           WHEN 5 THEN 'investigating'
           WHEN 6 THEN 'wontfix'
           WHEN 7 THEN 'fixed'
           WHEN 8 THEN 'backedout'
           WHEN 9 THEN 'confirming'
       END AS status,
       amount_pct,
       amount_abs,
       prev_value,
       new_value,
       alert.manually_created,
       starred,
       push.revision as push_revision,
       repository.name AS repository,
       framework.name AS framework,
       signature.suite,
       signature.test,
       signature.extra_options,
       platform.platform,
       t_value,
       alert.created,
       alert.first_triaged,
       IF(alert.last_updated > summary.last_updated, alert.last_updated, summary.last_updated) as last_updated,
       summary.bug_updated,
       summary.bug_number,
       summary.notes
FROM performance_alert AS alert
INNER JOIN performance_alert_summary AS summary ON
((alert.related_summary_id IS NULL AND summary.id = alert.summary_id) OR summary.id = alert.related_summary_id)
OR (alert.created >= "%s" and summary.id = alert.summary_id)
INNER JOIN repository ON repository.id = summary.repository_id
INNER JOIN push AS push ON push.id = summary.push_id
INNER JOIN performance_signature AS signature ON signature.id = alert.series_signature_id
INNER JOIN machine_platform AS platform ON platform.id = signature.platform_id
INNER JOIN performance_framework AS framework ON framework.id = signature.framework_id
WHERE alert.last_updated >= "%s"
  AND alert.last_updated < "%s"
  OR alert.summary_id IN
    (SELECT id
     FROM performance_alert_summary
     WHERE last_updated >= "%s"
       AND last_updated < "%s")
]]


local commit_query_tmpl = [[
SELECT push.id AS push_id,
       push.time as push_time,
       push.revision AS push_revision,
       commit.revision AS commit_revision,
       commit.author,
       commit.comments
FROM push
LEFT JOIN
commit ON commit.push_id = push.id
WHERE push.time >= "%s"
  AND push.time < "%s"
]]


local alert_tmpl = [[
The bq load command has failed with return value: %d
cmd: %s
If this is an intermittent failure it can be ignored as it will automatically be retried.
]]


local function transform_alert(row)
    return
end


local function transform_commit(row)
    row.bug_number = tonumber(string.match(row.comments, "^%s*[Bb][uU][gG]%s+(%d+)")) -- nil if no bug #
end


local function process_results(cur, tname, transform)
    local fn = string.format("%s/%s_%s.json", batch_dir, read_config("Logger"), tname)
    local fh = assert(io.open(fn, "wb"))
    local cnt = 0
    local row = cur:fetch({}, "a")
    while row do
        transform(row)
        fh:write(cjson.encode(row), "\n")
        cnt = cnt + 1
        row = cur:fetch (row, "a")
    end
    fh:close()
    if cnt == 0 then return true end

    local bq_cmd = string.format("bq load --source_format NEWLINE_DELIMITED_JSON --ignore_unknown_values %s.%s %s",
                                 bq_dataset, tname, fn)
    local rv = os.execute(bq_cmd)
    if rv ~= 0 then
        alert.send(read_config("Logger"), "bq load", string.format(alert_tmpl, rv / 256, bq_cmd))
        return false
    end

    return true
end


local function run_query(q, st, et, tname, transform)
    local time_t = st
    local con, err = env:connect(db, db_user, db_pass, db_host, db_port, nil, 2048)
    if not con then
        print("no connection", err)
        return time_t
    end

    local cur, err = con:execute(q)
    if not cur then
        con:close()
        print(err, q)
        return time_t
    end
    if process_results(cur, tname, transform) then time_t = et end
    cur:close()
    con:close()
    return time_t
end


function process_message(checkpoint)
    if checkpoint then
        local alert, commit = string.match(checkpoint, "^(%d+)\t(%d+)$")
        alert_day = tonumber(alert) or alert_day
        commit_day = tonumber(commit) or commit_day
    end

    local time_t    = os.time()
    local et        = get_start_of_day(time_t)
    local ets       = get_date(et)

    if time_t - alert_day >= 86400 + 3600 then
        local sts   = get_date(alert_day)
        local q     = string.format(alert_query_tmpl, sts, sts, ets, sts, ets)
        print(string.format("loading table: %s start: %s end: %s", bq_alert_table, sts, ets))
        alert_day   = run_query(q, alert_day, et, bq_alert_table, transform_alert)
    end

    if time_t - commit_day >= 86400 + 3600 then
        local sts   = get_date(commit_day)
        local q     = string.format(commit_query_tmpl, sts, ets)
        print(string.format("loading table: %s start: %s end: %s", bq_commit_table, sts, ets))
        commit_day  = run_query(q, commit_day, et, bq_commit_table, transform_commit)
    end

    inject_message(nil, string.format("%d\t%d", alert_day, commit_day))
    return 0
end

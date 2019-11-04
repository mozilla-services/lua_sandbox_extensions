/*
if this is used as a daily rollup utilizing the partition index it can miss event blocks that span days
e.g. 2019-10-10T23:20:00 taskStart -> 2019-10-11T01:11:00 taskFinished

if desired we could count 40 minutes to Oct 10 and 71 minutes to Oct 11.  However, this assumes
missing events are due to the event spanning days. If not this could add a lot of invalid time to
the analysis.
*/

CREATE TEMP FUNCTION
  summary(a ARRAY<STRUCT<timestamp TIMESTAMP,
    eventType STRING>>)
  RETURNS STRUCT<timestamp TIMESTAMP,
  total NUMERIC,
  boot NUMERIC,
  idle NUMERIC,
  task NUMERIC,
  reboot NUMERIC>
  LANGUAGE js AS """
    var timestamp = null;
    var total = 0;
    var idle  = 0;
    var task  = 0;
    var boot  = 0;
    var reboot = 0;
    var boot_start = null;
    var idle_start = null;
    var task_start = null;
    var len = a.length;
    for (i=0; i < len; ++i) {
      if (idle_start) {
        idle += a[i].timestamp - idle_start;
        idle_start = null;
      }
      if (task_start) {
        task += a[i].timestamp - task_start;
        task_start = null;
      }

      var et = a[i].eventType;
      if (et == "workerReady") {
        idle_start = a[i].timestamp;
        if (boot_start) {
          boot += a[i].timestamp - boot_start;
          boot_start = null;
        }
      } else if (et == "taskStart") {
        task_start = a[i].timestamp;
      } else if (et == "instanceBoot") {
        boot_start = a[i].timestamp;
        if (i > 0) {
            reboot += boot_start - a[i - 1].timestamp;
        }
      }
    }
    if (len > 0) {
      timestamp = a[0].timestamp;
      total = a[len - 1].timestamp - a[0].timestamp;
    }
    return {timestamp:timestamp, total:total, boot:boot, idle:idle, task:task, reboot:reboot};
""";
WITH
  nested AS (
  SELECT
    workerId,
    STRING_AGG(DISTINCT workerPoolId) AS workerPoolId,
    ARRAY_AGG((timestamp,
        eventType)
    ORDER BY
      timestamp) AS events
  FROM
    taskclusteretl.worker_metrics
  WHERE
    eventType != "taskQueued"
  GROUP BY
    workerId),
  worker_summary AS (
  SELECT
    workerId,
    workerPoolId,
    summary(events) AS times
  FROM
    nested)
SELECT
  EXTRACT(date
  FROM
    times.timestamp) AS date,
  workerPoolId,
  SUM(times.boot) / 1000 AS boot_s,
  SUM(times.idle) / 1000 AS idle_s,
  SUM(times.task) / 1000 AS task_s,
  SUM(times.reboot) / 1000 AS reboot_s,
  SUM(times.total) / 1000 AS total_s,
  ROUND((SUM(times.task) / SUM(times.total) * 100), 2) AS utilization_pct
FROM
  worker_summary
GROUP BY
  date,
  workerPoolId

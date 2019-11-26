WITH
  a AS (
  SELECT
    date,
    provisionerId,
    workerType,
    SUM(TIMESTAMP_DIFF(resolved, started, millisecond)) / 3600000 AS used_hours
  FROM
    taskclusteretl.derived_task_summary
  WHERE
    date = DATE_SUB(@run_date, INTERVAL 2 day)
  GROUP BY
    date,
    provisionerId,
    workerType),
  b AS (
  SELECT
    date,
    provisionerId,
    workerType,
    hours,
    cost_per_ms
  FROM
    taskclusteretl.derived_daily_cost_per_workertype
  WHERE
    date = DATE_SUB(@run_date, INTERVAL 2 day))
SELECT
  b.date,
  "-overhead-" AS project,
  "-overhead-" AS platform,
  "-overhead-" AS kind,
  "-overhead-" AS owner,
  0 AS tier,
  b.provisionerId,
  b.workerType,
  b.hours - ifnull(used_hours,
    0) AS hours,
  ((b.hours - ifnull(used_hours,
        0)) * 3600 * 1000) * cost_per_ms AS cost
FROM
  a
RIGHT JOIN
  b
ON
  a.date = b.date
  AND (a.provisionerId is null or a.provisionerId = b.provisionerId)
  AND a.workerType = b.workerType

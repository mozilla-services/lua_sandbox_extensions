WITH
  a AS (
  SELECT
    MIN(date) AS date,
    project,
    taskGroupId,
    SUM(tasks) AS tasks,
    SUM(seconds) AS total_seconds,
    SUM(cost) AS cost
  FROM
    taskclusteretl.derived_kind_costs
  WHERE
    date = DATE_SUB(@run_date, INTERVAL 1 day)
  GROUP BY
    taskGroupId,
    project),
  b AS (
  SELECT
    taskGroupId,
    MIN(started) AS started,
    MAX(resolved) AS resolved
  FROM
    taskclusteretl.derived_task_summary dts
  GROUP BY
    taskGroupId)
SELECT
  a.*,
  b.started,
  b.resolved,
  TIMESTAMP_DIFF(b.resolved, b.started, millisecond) / 1000 AS wall_clock_seconds
FROM
  a
JOIN
  b
ON
  a.taskGroupId = b.taskGroupId
GROUP BY
  taskGroupId,
  a.date,
  a.project,
  a.tasks,
  a.total_seconds,
  a.cost,
  b.started,
  b.resolved

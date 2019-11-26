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
    date = DATE_SUB(@run_date, INTERVAL 2 day)
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
  TIMESTAMP_DIFF(b.resolved, b.started, millisecond) / 1000 AS wall_clock_seconds,
  release_promotion_flavor,
  build_number,
  release_version,
  action,
  tasks_for
FROM
  a
JOIN
  b
ON
  a.taskGroupId = b.taskGroupId
JOIN (
  SELECT
    taskId,
    JSON_EXTRACT_SCALAR(extra,
      "$.action.context.input.release_promotion_flavor") AS release_promotion_flavor,
    JSON_EXTRACT_SCALAR(extra,
      "$.action.context.input.build_number") AS build_number,
    JSON_EXTRACT_SCALAR(extra,
      "$.action.context.input.version") AS release_version,
    JSON_EXTRACT_SCALAR(extra,
      "$.action.name") AS action,
    JSON_EXTRACT_SCALAR(extra,
      "$.tasks_for") AS tasks_for
  FROM
    taskclusteretl.task_definition )
ON
  taskId = a.taskGroupId
GROUP BY
  taskGroupId,
  a.date,
  a.project,
  a.tasks,
  a.total_seconds,
  a.cost,
  b.started,
  b.resolved,
  release_promotion_flavor,
  build_number,
  release_version,
  action,
  tasks_for

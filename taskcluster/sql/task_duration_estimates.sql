SELECT
  DISTINCT -- in some use cases there are exact duplicate submissions e.g. exception, canceled
  COUNT(started) as tasks_considered,
  ROUND(AVG(TIMESTAMP_DIFF(resolved, started, millisecond)) / 1000, 2) AS mean_duration_seconds,
  name
FROM
  taskclusteretl.derived_task_summary timing
JOIN (
  SELECT
    taskId,
    metadata.name as name
  FROM
    taskclusteretl.task_definition ) defs
ON
  timing.taskId = defs.taskId
WHERE
  started >= CAST(DATE_SUB(@run_date, INTERVAL 30 day) AS timestamp)
  AND resolved < CAST(@run_time AS timestamp)
GROUP by name
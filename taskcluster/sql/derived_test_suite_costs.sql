WITH
  tid AS (
  SELECT
    taskId,
    JSON_EXTRACT_SCALAR(extra,
      "$.suite") AS suite
  FROM
    taskclusteretl.task_definition
  WHERE
    created >= CAST(DATE_SUB(@run_date, INTERVAL 2 day) AS timestamp) -- scan a day earlier for tasks created here but not run until the next day
    AND created < CAST(DATE(@run_time) AS timestamp)
    AND JSON_EXTRACT_SCALAR(extra,
      "$.suite") IS NOT NULL )
  --- if this is a common query suite should be added to the timing table
SELECT
  EXTRACT(date
  FROM
    logStart) AS date,
  project,
  platform,
  t.workerType,
  ARRAY_TO_STRING(collection, ",") AS collection,
  tid.suite,
  tier,
  COUNT(*) AS tasks,
  ROUND(SUM(TIMESTAMP_DIFF(resolved, started, millisecond)) / 3600000, 2) AS hours,
  ROUND(SUM(TIMESTAMP_DIFF(resolved, started, millisecond)) * (
    SELECT
      cost_per_ms
    FROM
      taskclusteretl.derived_cost_per_workertype AS tmp
    WHERE
      t.workerType = tmp.workerType
      AND tmp.date = "2019-07-01"), 2) AS cost
      --DATE(EXTRACT(year
      --  FROM
      --    @run_date), EXTRACT(month
      --  FROM
      --    @run_date), 1)), 2) AS cost -- this allows us to see the missing cost data
FROM
  taskclusteretl.timing AS t,
  --taskclusteretl.derived_cost_per_workertype AS cpw,
  tid
WHERE
  logStart >= CAST(DATE_SUB(@run_date, INTERVAL 1 day) AS timestamp)
  AND logStart < CAST(DATE(@run_time) AS timestamp)
  AND level = 0
  AND t.taskId = tid.taskId
  --AND t.workerType = cpw.workerType AND cpw.date = DATE(EXTRACT(year FROM logStart), EXTRACT(month FROM logStart), 1)
GROUP BY
  date,
  project,
  platform,
  workerType,
  collection,
  tid.suite,
  tier

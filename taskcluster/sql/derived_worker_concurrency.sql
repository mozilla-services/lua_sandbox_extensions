WITH
  a AS (
  SELECT
    t1.date,
    t1.provisionerId,
    t1.workerType,
    COUNT(DISTINCT(CONCAT(t1.taskId, "_", CAST(t1.runId AS string)))) AS tasks,
    APPROX_TOP_COUNT(CONCAT(t1.taskId, "_", CAST(t1.runId AS string)), 10000)[
  OFFSET
    (0)].count AS approx_peak_concurrent_tasks,
    SUM(CASE
        WHEN t1.taskId = t2.taskId THEN TIMESTAMP_DIFF(t2.resolved, t2.started, MILLISECOND)
      ELSE
      0
    END
      ) / 1000 AS total_sequential,
    SUM(CASE
        WHEN t1.taskId = t2.taskId OR (t1.started = t2.resolved AND t1.taskId > t2.taskId) THEN 0 -- remove self (a-a) and one symetric (a-b, b-a) overlap
        WHEN t1.resolved < t2.resolved THEN TIMESTAMP_DIFF(t1.resolved, t1.started, MILLISECOND)
      ELSE
      TIMESTAMP_DIFF(t2.resolved, t1.started, MILLISECOND)
    END
      ) / 1000 AS x_task_overlap,
    SUM(CASE
        WHEN t1.taskId = t2.taskId OR (t1.started = t2.started AND t1.taskId > t2.taskId) THEN 0
      ELSE
      TIMESTAMP_DIFF(t2.resolved, t2.started, MILLISECOND)
    END
      ) / 1000 AS max_x_task_overlap
  FROM
    taskclusteretl.derived_task_summary t1,
    taskclusteretl.derived_task_summary t2
  WHERE
    t1.started >= t2.started
    AND t1.started < t2.resolved
    AND (t1.provisionerId is NULL or t1.provisionerId = t2.provisionerId)
    AND t1.workerType = t2.workerType
    AND ( t2.started >= CAST(DATE_SUB(@run_date, INTERVAL 1 day) AS timestamp)
      AND t2.started < CAST(DATE(@run_time) AS timestamp)
      OR t2.resolved >= CAST(DATE_SUB(@run_date, INTERVAL 1 day) AS timestamp)
      AND t2.resolved < CAST(DATE(@run_time) AS timestamp)) -- handle outer tasks that span days
    -- restrict to the correct partitions
    AND t1.date = DATE_SUB(@run_date, INTERVAL 1 day)
    AND (t2.date = DATE_SUB(@run_date, INTERVAL 2 day)
      OR t2.date = DATE_SUB(@run_date, INTERVAL 1 day)) -- limit the outer tasks to a two day window (to reduce the table scan)
  GROUP BY
    date,
    provisionerId,
    workerType
  ORDER BY
    date,
    provisionerId,
    workerType)
SELECT
  *,
  ifnull(ROUND(safe_divide(x_task_overlap,
        max_x_task_overlap) * 100, 2),
    0) AS x_task_overlap_pct -- of the areas that do overlap, this is the percentage of overlap
FROM
  a

SELECT
  date,
  project,
  platform,
  workerType,
  collection,
  suite,
  tier,
  COUNT(*) AS tasks,
  ROUND(SUM(TIMESTAMP_DIFF(resolved, started, millisecond)) / 3600000, 2) AS hours,
  ROUND(SUM(TIMESTAMP_DIFF(resolved, started, millisecond)) * ifnull((
    SELECT
      cost_per_ms
    FROM
      taskclusteretl.derived_cost_per_workertype AS tmp
    WHERE
      tmp.workerType = dts.workerType
      AND tmp.date = date(extract(year from dts.date), extract(month from dts.date), 1)),
    (
    SELECT
      cost_per_ms
    FROM
      taskclusteretl.derived_cost_per_workertype AS tmp
    WHERE
      tmp.workerType = dts.workerType
      AND tmp.date = "1970-01-01")), 2) AS cost -- 1970-01-01 stores the most recent cost we have for each workerType (since the manual data load is 4-6 weeks behind)
FROM
  taskclusteretl.derived_task_summary as dts
WHERE
  date = DATE_SUB(@run_date, INTERVAL 1 day)
  and suite is not NULL
GROUP BY
  date,
  project,
  platform,
  workerType,
  collection,
  suite,
  tier

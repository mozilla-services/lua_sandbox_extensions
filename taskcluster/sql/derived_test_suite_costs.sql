DELETE
FROM
  taskclusteretl.derived_test_suite_costs
WHERE
  date >= DATE_SUB(CURRENT_DATE(), INTERVAL 5 day)
  AND date < CURRENT_DATE();
INSERT INTO
  taskclusteretl.derived_test_suite_costs
WITH
  a AS (
  SELECT
    date,
    project,
    platform,
    provisionerId,
    workerType,
    collection,
    suite,
    tier,
    owner,
    COUNT(*) AS tasks,
    ROUND(SUM(TIMESTAMP_DIFF(resolved, started, millisecond)) / 3600000, 2) AS hours,
    ROUND(SUM(TIMESTAMP_DIFF(resolved, started, millisecond)) * (
      SELECT
        cost_per_ms
      FROM
        taskclusteretl.derived_daily_cost_per_workertype AS tmp
      WHERE
        (tmp.provisionerId IS NULL
          AND dts.provisionerId IS NULL
          OR tmp.provisionerId = dts.provisionerId)
        AND tmp.workerType = dts.workerType
        AND tmp.date = dts.date), 2) AS cost
  FROM
    taskclusteretl.derived_task_summary AS dts
  WHERE
    date >= DATE_SUB(CURRENT_DATE(), INTERVAL 5 day)
    AND date < CURRENT_DATE()
    AND kind = "test"
  GROUP BY
    date,
    project,
    platform,
    provisionerId,
    workerType,
    collection,
    suite,
    tier,
    owner)
SELECT
  a.*,
  name AS owner_name,
  manager AS manager_name
FROM
  a
LEFT JOIN (
  SELECT
    email,
    name,
    manager
  FROM
    taskclusteretl.mozilla_com)
ON
  email = a.owner

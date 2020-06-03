DECLARE start_date DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 5 day);
DECLARE end_date DATE DEFAULT CURRENT_DATE();

DELETE
FROM
  taskclusteretl.derived_test_suite_costs
WHERE
  date >= start_date
  AND date < end_date;
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
    SUM(TIMESTAMP_DIFF(resolved, started, millisecond)) / 3600000 AS hours,
    SUM(TIMESTAMP_DIFF(resolved, started, millisecond)) * (
      IF
        (workerGroup LIKE "mdc_",
          (
          SELECT
            sum(cost_per_ms)
          FROM
            taskclusteretl.derived_daily_cost_per_workertype AS tmp
          WHERE
            (cluster IS NULL
              OR cluster = "firefox")
            AND (tmp.provisionerId IS NULL
              AND dts.provisionerId IS NULL
              OR tmp.provisionerId = dts.provisionerId)
            AND tmp.workerType = dts.workerType
            AND tmp.date = dts.date
            AND tmp.cost_origin = workerGroup),
          (
          SELECT
            sum(cost_per_ms)
          FROM
            taskclusteretl.derived_daily_cost_per_workertype AS tmp
          WHERE
            (cluster IS NULL
              OR cluster = "firefox")
            AND (tmp.provisionerId IS NULL
              AND dts.provisionerId IS NULL
              OR tmp.provisionerId = dts.provisionerId)
            AND tmp.workerType = dts.workerType
            AND tmp.date = dts.date))) AS cost,
    workerGroup
  FROM
    taskclusteretl.derived_task_summary AS dts
  WHERE
    date >= start_date
    AND date < end_date
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
    owner,
    workerGroup)
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
  tasks,
  hours,
  cost,
  ifnull(name,
    a.owner) AS owner_name,
  manager AS manager_name,
  workerGroup
FROM
  a
LEFT JOIN (
  SELECT
    email,
    name,
    manager
  FROM
    taskclusteretl.person_mozilla_com)
ON
  email = a.owner

DECLARE start_date DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 5 day);
DECLARE end_date DATE DEFAULT CURRENT_DATE();

DELETE
FROM
  taskclusteretl.derived_kind_costs
WHERE
  date >= start_date
  AND date < end_date;
INSERT INTO
  taskclusteretl.derived_kind_costs
WITH
  a AS (
  SELECT
    date,
    project,
    platform,
    collection,
    kind,
    provisionerId,
    workerType,
    taskGroupId,
    owner,
    COUNT(*) AS tasks,
    SUM(TIMESTAMP_DIFF(resolved, started, millisecond)) / 1000 AS seconds,
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
    AND execution > 0
  GROUP BY
    date,
    project,
    platform,
    collection,
    kind,
    provisionerId,
    workerType,
    taskGroupId,
    owner,
    workerGroup)
SELECT
  date,
  project,
  platform,
  collection,
  kind,
  provisionerId,
  workerType,
  taskGroupId,
  owner,
  tasks,
  seconds,
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

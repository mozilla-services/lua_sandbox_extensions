DELETE
FROM
  taskclusteretl.derived_workertype_costs
WHERE
  date >= DATE_SUB(CURRENT_DATE(), INTERVAL 5 day)
  AND date < CURRENT_DATE();
INSERT INTO
  taskclusteretl.derived_workertype_costs
WITH
  time AS (
  SELECT
    date,
    provisionerId,
    workerType,
    project,
    platform,
    taskGroupId,
    collection,
    suite,
    tier,
    kind,
    owner,
    COUNT(*) AS tasks,
    SUM(TIMESTAMP_DIFF(resolved, started, millisecond)) / 3600000 AS hours
  FROM
    taskclusteretl.derived_task_summary
  WHERE
    date >= DATE_SUB(CURRENT_DATE(), INTERVAL 5 day)
    AND date < CURRENT_DATE()
  GROUP BY
    date,
    provisionerId,
    workerType,
    project,
    platform,
    taskGroupId,
    collection,
    suite,
    tier,
    kind,
    owner),
  cost AS (
  SELECT
    time.*,
    ROUND(time.hours * 3600 * 1000 * cost_per_ms, 2) AS cost,
    cost_origin
  FROM
    time
  LEFT JOIN (
    SELECT
      *
    FROM
      taskclusteretl.derived_daily_cost_per_workertype
    WHERE
      cluster IS NULL
      OR cluster = "firefox") AS ddcpw
  ON
    (ddcpw.provisionerId IS NULL
      OR ddcpw.provisionerId = time.provisionerId)
    AND (ddcpw.workerType IS NULL
      AND time.workerType IS NULL
      OR ddcpw.workerType = time.workerType)
    AND ddcpw.date = time.date),
  owner AS (
  SELECT
    cost.*,
    ifnull(name,
      cost.owner) AS owner_name,
    manager AS manager_name
  FROM
    cost
  LEFT JOIN (
    SELECT
      email,
      name,
      manager
    FROM
      taskclusteretl.person_mozilla_com)
  ON
    email = cost.owner),
  used AS (
  SELECT
    date,
    provisionerId,
    workerType,
    SUM(TIMESTAMP_DIFF(resolved, started, millisecond)) / 3600000 AS used_hours
  FROM
    taskclusteretl.derived_task_summary
  WHERE
    date >= DATE_SUB(CURRENT_DATE(), INTERVAL 5 day)
    AND date < CURRENT_DATE()
  GROUP BY
    date,
    provisionerId,
    workerType),
  unused AS (
  SELECT
    *
  FROM
    taskclusteretl.derived_daily_cost_per_workertype
  WHERE
    (cluster IS NULL
      OR cluster = "firefox")
    AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL 5 day)
    AND date < CURRENT_DATE() ),
  overhead AS (
  SELECT
    unused.date,
    unused.provisionerId,
    unused.workerType,
    "-overhead-" AS project,
    "-overhead-" AS platform,
    CAST(NULL AS string) AS taskGroupId,
    CAST(NULL AS string) AS collection,
    CAST(NULL AS string) AS suite,
    0 AS tier,
    "-overhead-" AS kind,
    "-overhead-" AS owner,
    0 AS tasks,
    unused.hours - ifnull(used_hours,
      0) AS hours,
  IF
    (unused.hours IS NULL,
      unused.cost,
      (unused.hours - ifnull(used_hours,
          0)) * 3600 * 1000 * cost_per_ms) AS cost,
    cost_origin,
    CAST(NULL AS string) AS owner_name,
    CAST(NULL AS ARRAY<string>) AS manager_name
  FROM
    used
  RIGHT JOIN
    unused
  ON
    used.date = unused.date
    AND (used.provisionerId IS NULL
      AND unused.provisionerId IS NULL
      OR used.provisionerId = unused.provisionerId)
    AND (used.workerType IS NULL
      AND unused.workerType IS NULL
      OR used.workerType = unused.workerType))
SELECT
  *
FROM
  owner
UNION ALL
SELECT
  *
FROM
  overhead

DECLARE start_date DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 5 day);
DECLARE end_date DATE DEFAULT CURRENT_DATE();

DELETE
FROM
  taskclusteretl_community.derived_workertype_costs
WHERE
  date >= start_date
  AND date < end_date;
INSERT INTO
  taskclusteretl_community.derived_workertype_costs
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
    SUM(TIMESTAMP_DIFF(resolved, started, millisecond)) / 3600000 AS hours,
    -- have to special case our data centers since the workerPoolIds are not unique and both will be joined for every record
  IF
    (workerGroup LIKE "mdc_",
      workerGroup,
    IF
      (workerGroup = "signing-mac-v1"
        OR (workerGroup IS NULL
          AND provisionerId = "releng-hardware"),
      IF
        (FARM_FINGERPRINT(CAST(execution AS string)) < 0,
          "mdc1",
          "mdc2"),
        NULL)) AS workerGroup
  FROM
    taskclusteretl_community.derived_task_summary
  WHERE
    date >= start_date
    AND date < end_date
    AND execution > 0
  GROUP BY
    date,
    provisionerId,
    workerType,
    workerGroup,
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
    time.* EXCEPT(tasks,
      hours,
      workerGroup),
  IF
    (ddcpw.cost IS NULL
      OR ddcpw.hours IS NOT NULL,
      tasks,
      NULL) AS tasks,
  IF
    (ddcpw.cost IS NULL
      OR ddcpw.hours IS NOT NULL,
      time.hours,
      NULL) AS hours,
    time.hours * 3600 * 1000 * cost_per_ms AS cost,
    cost_origin,
    description
  FROM
    time
  LEFT JOIN (
    SELECT
      *
    FROM
      taskclusteretl.derived_daily_cost_per_workertype
    WHERE
      cluster = "community"
      AND date >= start_date
      AND date < end_date
      AND cost_per_ms IS NOT NULL) AS ddcpw
  ON
    (ddcpw.provisionerId IS NULL
      AND time.provisionerId IS NULL
      OR ddcpw.provisionerId = time.provisionerId)
    AND (ddcpw.workerType IS NULL
      AND time.workerType IS NULL
      OR ddcpw.workerType = time.workerType)
    AND (time.workerGroup IS NULL
      OR ddcpw.cost_origin = time.workerGroup) -- further disambiguation to match the cost to the correct Mozilla datacenter
    AND ddcpw.date = time.date),
  owner AS (
  SELECT
    cost.* EXCEPT(description),
    ifnull(name,
      cost.owner) AS owner_name,
    IFNULL(manager,
      ["Collaborator",
      "Mitchell Baker"]) AS manager_name,
    cost.description
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
    SUM(TIMESTAMP_DIFF(resolved, started, millisecond)) / 3600000 AS hours,
  IF
    (workerGroup LIKE "mdc_",
      workerGroup,
    IF
      (workerGroup = "signing-mac-v1"
        OR (workerGroup IS NULL
          AND provisionerId = "releng-hardware"),
      IF
        (FARM_FINGERPRINT(CAST(execution AS string)) < 0,
          "mdc1",
          "mdc2"),
        NULL)) AS workerGroup
  FROM
    taskclusteretl_community.derived_task_summary
  WHERE
    date >= start_date
    AND date < end_date
  GROUP BY
    date,
    provisionerId,
    workerType,
    workerGroup
  HAVING
    hours != 0),
  total AS (
  SELECT
    *
  FROM
    taskclusteretl.derived_daily_cost_per_workertype
  WHERE
    cluster = "community"
    AND date >= start_date
    AND date < end_date
    AND hours IS NOT NULL),
  overhead AS (
  SELECT
    total.date,
    total.provisionerId,
    total.workerType,
    total.cost_origin,
    total.hours - ifnull(used.hours,
      0) AS hours,
    total.description
  FROM
    used
  RIGHT JOIN
    total
  ON
    used.date = total.date
    AND (used.provisionerId IS NULL
      AND total.provisionerId IS NULL
      OR used.provisionerId = total.provisionerId)
    AND (used.workerType IS NULL
      AND total.workerType IS NULL
      OR used.workerType = total.workerType)
    AND (used.workerGroup IS NULL
      OR total.cost_origin = used.workerGroup)),
  overhead_cost AS (
  SELECT
    overhead.date,
    overhead.provisionerId,
    overhead.workerType,
    "-overhead-" AS project,
    "-overhead-" AS platform,
    CAST(NULL AS string) AS taskGroupId,
    CAST(NULL AS string) AS collection,
    CAST(NULL AS string) AS suite,
    0 AS tier,
    "-overhead-" AS kind,
    "-overhead-" AS owner,
    CAST(NULL AS INT64) AS tasks,
  IF
    (ddcpw.hours IS NOT NULL,
      overhead.hours,
      NULL) AS hours,
    overhead.hours * 3600 * 1000 * cost_per_ms AS cost,
    overhead.cost_origin,
    CAST(NULL AS string) AS owner_name,
    CAST(NULL AS ARRAY<string>) AS manager_name,
    ddcpw.description
  FROM
    overhead
  LEFT JOIN (
    SELECT
      *
    FROM
      taskclusteretl.derived_daily_cost_per_workertype
    WHERE
      cluster = "community"
      AND date >= start_date
      AND date < end_date
      AND cost_per_ms IS NOT NULL) AS ddcpw
  ON
    (ddcpw.provisionerId IS NULL
      AND overhead.provisionerId IS NULL
      OR ddcpw.provisionerId = overhead.provisionerId)
    AND (ddcpw.workerType IS NULL
      AND overhead.workerType IS NULL
      OR ddcpw.workerType = overhead.workerType)
    AND (overhead.cost_origin IS NULL
      OR ddcpw.cost_origin = overhead.cost_origin)
    AND ddcpw.date = overhead.date
    AND (ddcpw.hours IS NULL
      OR ddcpw.description = overhead.description)),
  overhead_notime AS (
  SELECT
    date,
    provisionerId,
    workerType,
    "-overhead-" AS project,
    "-overhead-" AS platform,
    CAST(NULL AS string) AS taskGroupId,
    CAST(NULL AS string) AS collection,
    CAST(NULL AS string) AS suite,
    0 AS tier,
    "-overhead-" AS kind,
    "-overhead-" AS owner,
    CAST(NULL AS INT64) AS tasks,
    CAST(NULL AS float64) AS hours,
    cost,
    cost_origin,
    CAST(NULL AS string) AS owner_name,
    CAST(NULL AS ARRAY<string>) AS manager_name,
    description
  FROM
    taskclusteretl.derived_daily_cost_per_workertype
  WHERE
    cluster = "community"
    AND date >= start_date
    AND date < end_date
    AND (hours IS NULL
      AND cost_per_ms IS NULL))
SELECT
  *
FROM
  owner
UNION ALL
SELECT
  *
FROM
  overhead_cost
UNION ALL
SELECT
  *
FROM
  overhead_notime

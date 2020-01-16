DELETE
FROM
  taskclusteretl.derived_daily_cost_per_workertype
WHERE
  date >= DATE_SUB(CURRENT_DATE(), INTERVAL 5 day)
  AND date < CURRENT_DATE();
INSERT INTO
  taskclusteretl.derived_daily_cost_per_workertype
WITH
  data AS (
  SELECT
    *
  FROM
    `jthomas-billing.billing.aws_billing_v1`
  INNER JOIN
    `jthomas-billing.billing.aws_billing_latest_reports_v1`
  USING
    (billing_assembly_id) ),
  rate AS (
  SELECT
    usage_start_date,
    resourcetags_user_name,
    SUM(lineitem_unblendedcost) AS cost,
    SUM(
    IF
      (pricing_unit = "Hours"
        OR pricing_unit = "Hrs"
        OR (pricing_unit IS NULL
          AND lineitem_lineitemdescription LIKE "%Spot Instance-hour%"),
        lineitem_usageamount,
        NULL)) AS hours,
    CASE lineitem_usageaccountid
      WHEN 692406183521 THEN "firefox"      -- TaskCluster Platform - 8100
      WHEN 43838267467 THEN "firefox"      -- cloudops-taskcluster-aws-prod
      WHEN 885316786408 THEN "community" -- moz-fx-tc-community-workers
      WHEN 710952102342 THEN "staging"   -- taskcluster-aws-staging
      WHEN 897777688886 THEN "staging"   -- cloudops-taskcluster-aws-stage
      WHEN 400370709957 THEN "staging"   -- taskcluster-provisioner-staging
  END
    AS cluster
  FROM
    data
  WHERE
    lineitem_usageaccountid IN ( 692406183521,
      43838267467,
      885316786408,
      710952102342,
      897777688886,
      400370709957)
    AND usage_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 5 day)
    AND usage_start_date < CURRENT_DATE()
  GROUP BY
    usage_start_date,
    resourcetags_user_name,
    cluster),
  releng AS (
  SELECT
    date,
    provisionerId,
    workerType,
    (24 * instances * 3600 * 1000 * cost_per_ms) AS cost,
    (24 * instances) AS hours,
    cost_per_ms,
    "releng" AS cost_origin,
    CAST(NULL AS string) AS cluster
  FROM
    taskclusteretl.releng_hardware
  CROSS JOIN
    UNNEST(GENERATE_DATE_ARRAY(DATE_SUB(CURRENT_DATE(), INTERVAL 5 day), DATE_SUB(CURRENT_DATE(), INTERVAL 1 day))) AS date),
  aws AS (
  SELECT
    usage_start_date AS date,
    REGEXP_EXTRACT(resourcetags_user_name, "(.+)/.+") AS provisionerId,
    ifnull(REGEXP_EXTRACT(resourcetags_user_name, ".+/(.+)"),
      resourcetags_user_name) AS workerType,
    SUM(cost) AS cost,
    SUM(hours) AS hours,
    SUM(cost) / (ifnull(SUM(hours),
        24) * 3600 * 1000) AS cost_per_ms,
    "aws" AS cost_origin,
    cluster
  FROM
    rate
  GROUP BY
    date,
    provisionerId,
    workerType,
    cost_origin,
    cluster),
  gcp AS (
  SELECT
    EXTRACT(date
    FROM
      usage_start_time) date,
    (
    SELECT
      CASE
        WHEN STARTS_WITH(value, "proj-git-cinnabar") THEN "proj-git-cinnabar"
        WHEN STARTS_WITH(value, "proj-bors-ng") THEN "proj-git-cinnabar"
        WHEN REGEXP_CONTAINS(value, "_") THEN REGEXP_EXTRACT(value, "([^_]+)")
      ELSE
      REGEXP_EXTRACT(value, "([^-]+\\-[^-]+)")
    END
    FROM
      UNNEST(labels)
    WHERE
      key = "worker-pool-id") AS provisionerId,
    (
    SELECT
      CASE
        WHEN STARTS_WITH(value, "proj-git-cinnabar") OR STARTS_WITH(value, "proj-bors-ng") THEN REGEXP_EXTRACT(value, "[^-]+\\-[^-]+\\-[^-]+\\-(.*)")
        WHEN REGEXP_CONTAINS(value, "_") THEN REGEXP_EXTRACT(value, "[^_]+_(.+)")
      ELSE
      REGEXP_EXTRACT(value, "[^-]+\\-[^-]+\\-(.*)")
    END
    FROM
      UNNEST(labels)
    WHERE
      key = "worker-pool-id") AS workerType,
    SUM(cost) + SUM(IFNULL((
        SELECT
          SUM(c.amount)
        FROM
          UNNEST(credits) c),
        0)) AS cost,
    SUM(
    IF
      (usage.unit = "seconds",
        usage.amount,
        NULL)) / 3600 AS hours,
    SUM(cost) / (ifnull(SUM(
        IF
          (usage.unit = "seconds",
            usage.amount,
            NULL)),
        86400) * 1000) AS cost_per_ms,
    -- if there is no timing information divide the cost over the entire day
    "gcp" AS cost_origin,
    CASE
      WHEN STARTS_WITH(project.id, "fxci-prod") THEN "firefox"
      WHEN STARTS_WITH(project.id, "fxci-stag") THEN "stage"
    ELSE
    REGEXP_EXTRACT(project.id, "([^-]+)")
  END
    AS cluster
  FROM
    `moz-fx-billing-212017.billing.gcp_billing_export_v1_01E7D5_97288E_E2EBA0`
  WHERE
    _PARTITIONTIME >= CAST(DATE_SUB(CURRENT_DATE(), INTERVAL 5 day) AS timestamp)
    AND _PARTITIONTIME < CAST(CURRENT_DATE() AS timestamp)
    AND EXTRACT(date
    FROM
      usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 5 day)
    AND EXISTS (
    SELECT
      value
    FROM
      UNNEST(labels)
    WHERE
      key = "managed-by"
      AND value = "taskcluster")
  GROUP BY
    date,
    provisionerId,
    workerType,
    cost_origin,
    cluster)
SELECT
  *
FROM
  aws
UNION ALL
SELECT
  *
FROM
  releng
UNION ALL
SELECT
  *
FROM
  gcp

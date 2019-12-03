DELETE
FROM
  taskclusteretl.derived_daily_cost_per_workertype
WHERE
  date >= DATE_SUB(CURRENT_DATE(), INTERVAL 5 day)
  AND date < CURRENT_DATE();
INSERT INTO
  taskclusteretl.derived_daily_cost_per_workertype
WITH
  ids AS (
  SELECT
    account_id
  FROM
    `jthomas-billing.billing.aws_programs`
  WHERE
    program = 'taskcluster'),
  data AS (
  SELECT
    *
  FROM
    `jthomas-billing.billing.aws_billing_v1`
  INNER JOIN
    `jthomas-billing.billing.aws_billing_latest_reports_v1`
  USING
    (billing_assembly_id) ),
  rates AS (
  SELECT
    usage_start_date,
    lineitem_resourceid,
    resourcetags_user_name,
    SUM(lineitem_unblendedcost) AS cost,
    SUM(
    IF
      (pricing_unit = "Hours"
        OR pricing_unit = "Hrs"
        OR (pricing_unit IS NULL
          AND lineitem_lineitemdescription LIKE "%Spot Instance-hour%"),
        lineitem_usageamount,
        0)) AS hours
  FROM
    data
  WHERE
    resourcetags_user_name IS NOT NULL
    AND lineitem_usageaccountid IN (
    SELECT
      *
    FROM
      ids)
    AND usage_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 5 day)
    AND usage_start_date < CURRENT_DATE()
  GROUP BY
    usage_start_date,
    lineitem_resourceid,
    resourcetags_user_name),
  rate AS (
  SELECT
    usage_start_date,
    resourcetags_user_name,
    SUM(cost) AS cost,
    SUM(hours) AS hours
  FROM
    rates
  GROUP BY
    usage_start_date,
    resourcetags_user_name),
  releng AS (
  SELECT
    date,
    provisionerId,
    workerType,
    (24 * instances * 3600 * 1000 * cost_per_ms) AS cost,
    (24 * instances) AS hours,
    cost_per_ms,
    "releng" AS cost_origin
  FROM
    taskclusteretl.releng_hardware
  CROSS JOIN
    UNNEST(GENERATE_DATE_ARRAY(DATE_SUB(CURRENT_DATE(), INTERVAL 5 day), DATE_SUB(CURRENT_DATE(), INTERVAL 1 day))) AS date),
  billing AS (
  SELECT
    usage_start_date AS date,
    REGEXP_EXTRACT(resourcetags_user_name, "(.+)/.+") AS provisionerId,
    ifnull(REGEXP_EXTRACT(resourcetags_user_name, ".+/(.+)"),
      resourcetags_user_name) AS workerType,
    SUM(cost) AS cost,
    SUM(hours) AS hours,
    safe_divide(SUM(cost),
      SUM(hours) * 3600 * 1000) AS cost_per_ms,
    "aws" AS cost_origin
  FROM
    rate
  GROUP BY
    date,
    provisionerId,
    workerType,
    cost_origin
  HAVING
    hours > 0)
SELECT
  *
FROM
  billing
UNION ALL
SELECT
  *
FROM
  releng

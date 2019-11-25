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
  rates AS (
  SELECT
    usage_start_date,
    lineitem_resourceid,
    resourcetags_user_name AS resourcetags_user_name,
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
    AND resourcetags_user_owner = "release+tc-workers@mozilla.com"
    AND usage_start_date = DATE_SUB(@run_date, INTERVAL 2 day)
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
    DATE_SUB(@run_date, INTERVAL 1 day) AS date,
    provisionerId,
    workerType,
    (24 * instances) AS hours,
    (24 * instances * 3600 * 1000 * cost_per_ms) AS cost,
    cost_per_ms
  FROM
    taskclusteretl.releng_hardware),
  billing AS (
  SELECT
    usage_start_date AS date,
    REGEXP_EXTRACT(resourcetags_user_name, "(.+)/.+") AS provisionerId,
    ifnull(REGEXP_EXTRACT(resourcetags_user_name, ".+/(.+)"),
      resourcetags_user_name) AS workerType,
    SUM(cost) AS cost,
    SUM(hours) AS hours,
    safe_divide(SUM(cost),
      SUM(hours) * 3600 * 1000) AS cost_per_ms
  FROM
    rate
  GROUP BY
    date,
    provisionerId,
    workerType
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

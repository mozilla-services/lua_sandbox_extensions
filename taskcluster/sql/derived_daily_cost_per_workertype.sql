/*
##########################
The cost declarations above cannot be committed to this repository, they can be
reviewed/retrieved in BigQuery. A copy has been added to the relops financials
spreadsheet for backup purposes.
##########################
*/

DECLARE start_date DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 5 day);
DECLARE end_date DATE DEFAULT CURRENT_DATE();

DELETE
FROM
  taskclusteretl.derived_daily_cost_per_workertype
WHERE
  date >= start_date
  AND date < end_date;
INSERT INTO
  taskclusteretl.derived_daily_cost_per_workertype

WITH
/* Relops Cost Calculations are a bit different
1) total instances per cost_origin table
2) cost per instance broken out with a detailed description
3) number of used instances with a workerPoolId
4) unused (total - used)
*/

  relops_total_instances as (
    SELECT "bitbar" AS cost_origin, bitbar_instances AS instances, cast(null as string) as hardware union all
    SELECT "mdc1" AS cost_origin, mdc1_instances_mac AS instances, "mac" as hardware union all
    SELECT "mdc1" AS cost_origin,  mdc1_instances_moonshot AS instances, "moonshot" as hardware union all
    SELECT "mdc2" AS cost_origin, mdc2_instances_mac AS instances, "mac" as hardware union all
    SELECT "mdc2" AS cost_origin, mdc2_instances_moonshot AS instances, "moonshot" as hardware  union all
    SELECT "packet-sjc1" AS cost_origin, packet_instances AS instances, cast(null as string) as hardware union all
    SELECT "macosstadium" AS cost_origin, macosstadium_instances AS instances, cast(null as string) as hardware
  ),

  relops_instance_cost AS (
  SELECT "bitbar" AS cost_origin, bitbar_cloud / days_in_year AS cost, "Bitbar Private Cloud" AS description, cast(null as string) as hardware, TRUE AS has_hours union all
  SELECT "bitbar" AS cost_origin, bitbar_docker / days_in_year / bitbar_instances AS cost, "Custom Docker Framework Support" AS description, cast(null as string) as hardware, FALSE AS has_hours union all
  SELECT "bitbar" AS cost_origin, bitbar_support / days_in_year / bitbar_instances AS cost, "Enterprise Support" AS description, cast(null as string) as hardware, FALSE AS has_hours union all
  --SELECT "bitbar" AS cost_origin, bitbar_setup / days_in_year / bitbar_instances AS cost, "Setup" AS description, cast(null as string) as hardware, FALSE AS has_hours union all

  SELECT "mdc1" AS cost_origin, mdc1_rack / days_in_year / mdc1_instances AS cost, "Rack, power, cooling" AS description, cast(null as string) as hardware, FALSE AS has_hours union all
  SELECT "mdc1" AS cost_origin, mdc1_connectivity / days_in_year / mdc1_instances AS cost, "Connectivity" AS description, cast(null as string) as hardware, FALSE AS has_hours union all
  SELECT "mdc1" AS cost_origin, mdc1_remote / days_in_year / mdc1_instances AS cost, "Remote hands" AS description, cast(null as string) as hardware, FALSE AS has_hours union all
  SELECT "mdc1" AS cost_origin, mdc1_cross / days_in_year / mdc1_instances AS cost, "Cross connects" AS description, cast(null as string) as hardware, FALSE AS has_hours union all
  SELECT "mdc1" AS cost_origin, mac_cost / days_in_year / mac_instances AS cost, "Mac mini" AS description, "mac" as hardware, TRUE AS has_hours union all
  SELECT "mdc1" AS cost_origin, moonshot_cost / days_in_year / moonshot_instances AS cost, "HP Moonshot" AS description, "moonshot" as hardware, TRUE AS has_hours union all

  SELECT "mdc2" AS cost_origin, mdc2_rack / days_in_year / mdc2_instances AS cost, "Rack, power, cooling" AS description, cast(null as string) as hardware, FALSE AS has_hours union all
  SELECT "mdc2" AS cost_origin, mdc2_connectivity / days_in_year / mdc2_instances AS cost, "Connectivity" AS description, cast(null as string) as hardware, FALSE AS has_hours union all
  SELECT "mdc2" AS cost_origin, mdc2_remote / days_in_year / mdc2_instances AS cost, "Remote hands" AS description, cast(null as string) as hardware, FALSE AS has_hours union all
  SELECT "mdc2" AS cost_origin, mdc2_cross / days_in_year / mdc2_instances AS cost, "Cross connects" AS description, cast(null as string) as hardware, FALSE AS has_hours union all
  SELECT "mdc2" AS cost_origin, mac_cost / days_in_year / mac_instances AS cost, "Mac mini" AS description, "mac" as hardware, TRUE AS has_hours union all
  SELECT "mdc2" AS cost_origin, moonshot_cost / days_in_year / moonshot_instances AS cost, "HP Moonshot" AS description, "moonshot" as hardware, TRUE AS has_hours  union all

  SELECT "packet-sjc1" AS cost_origin, packet_bandwidth / 31 / packet_instances AS cost, "Outbound Bandwidth (bandwidth)" AS description, cast(null as string) as hardware, FALSE AS has_hours union all
  SELECT "packet-sjc1" AS cost_origin, packet_hardware / 31 / packet_instances AS cost, "c1.small.x86 (baremetal)" AS description, cast(null as string) as hardware, TRUE AS has_hours union all

  SELECT "macosstadium" AS cost_origin, macosstadium_hosting / 31 / macosstadium_instances AS cost, "Pro Hosting" AS description, cast(null as string) as hardware, FALSE AS has_hours union all
  SELECT "macosstadium" AS cost_origin, macosstadium_hardware / 31 / macosstadium_instances AS cost, "Mac mini i7 16GB/ 2x1TB RAID" AS description, cast(null as string) as hardware, TRUE AS has_hours
  ),

  relops_workers AS (
  SELECT
    EXTRACT(date
    FROM
      time) AS date,
    status.provisionerId,
    status.workerType,
    CASE
      WHEN workerGroup = "bitbar-sc" THEN "bitbar"
      -- releng-hardware add the mdcX 2020-02-01
      -- signing-mac-v1 has been changed to mdcX 2020-05-06
      WHEN workerGroup = "signing-mac-v1" or (workerGroup is NULL and status.provisionerId = "releng-hardware") THEN
  IF
    (FARM_FINGERPRINT(workerId) < 0,
      -- they are distributed about 50/50 so instead of an explict list just distribute them close to even
      "mdc1",
      -- there are multiple signing daemons on some boxes so the instance count is slightly inflated
      "mdc2")
    ELSE
    workerGroup
  END
    AS cost_origin,
    CASE
      WHEN workerGroup LIKE "mdc%" or (workerGroup is NULL and status.provisionerId = "releng-hardware") THEN IF (REGEXP_CONTAINS(status.workerType, "osx"), "mac", "moonshot")
      WHEN workerGroup = "signing-mac-v1" THEN "mac"
    ELSE
    NULL
  END
    AS hardware,
    COUNT(DISTINCT workerId) AS instances
  FROM
    taskclusteretl.pulse_task
  WHERE
    time >= CAST(start_date AS timestamp)
    AND time < CAST(end_date AS timestamp)
    AND workerId IS NOT NULL
    AND (workerGroup LIKE "mdc_"
      OR workerGroup LIKE "bitbar%"
      OR workerGroup = "packet-sjc1"
      OR workerGroup = "macosstadium"
      OR workerGroup = "signing-mac-v1"
      OR status.provisionerId = "releng-hardware") -- pre Feb 2020
  GROUP BY
    date,
    provisionerId,
    workerType,
    cost_origin,
    hardware),
  relops_used AS (
  SELECT
    date,
    cost_origin,
    hardware,
    SUM(instances) AS instances
  FROM
    relops_workers
  GROUP BY
    date,
    cost_origin,
    hardware
  ORDER BY
    date),
  relops_unused AS (
  SELECT
    rui.date,
    rui.cost_origin,
    rui.hardware,
    rti.instances - rui.instances AS unused_instances
  FROM
    relops_used AS rui
  LEFT JOIN
    relops_total_instances AS rti
  ON
    rti.cost_origin = rui.cost_origin
    AND ((rti.hardware IS NULL
        AND rui.hardware IS NULL)
      OR rti.hardware = rui.hardware)),
  relops AS (
  SELECT
    rwi.date,
    rwi.provisionerId,
    rwi.workerType,
    rwi.instances * roc.cost AS cost,
  IF
    (roc.has_hours,
      24.0 * instances,
      NULL) AS hours,
    roc.cost / (24.0 * 3600 * 1000) AS cost_per_ms,
    rwi.cost_origin,
    "firefox" AS cluster,
    roc.description
  FROM
    relops_workers AS rwi
  LEFT JOIN
    relops_instance_cost AS roc
  ON
    roc.cost_origin = rwi.cost_origin
    AND (roc.hardware IS NULL
      OR roc.hardware = rwi.hardware)),
  relops_overhead AS (
  SELECT
    rui.date,
    CAST(NULL AS string) AS provisionerId,
    CAST(NULL AS string) AS workerType,
    SUM(unused_instances * roc.cost) AS cost,
    SUM(
    IF
      (roc.has_hours,
        24.0 * unused_instances,
        NULL)) AS hours,
    MAX(roc.cost / (24.0 * 3600 * 1000)) AS cost_per_ms,
    rui.cost_origin,
    "firefox" AS cluster,
    roc.description
  FROM
    relops_unused AS rui
  LEFT JOIN
    relops_instance_cost AS roc
  ON
    roc.cost_origin = rui.cost_origin
    AND (roc.hardware IS NULL
      OR roc.hardware = rui.hardware)
  WHERE
    unused_instances > 0
  GROUP BY
    date,
    provisionerId,
    workerType,
    cost_origin,
    description),
  /* AWS Cost Calculations */ data AS (
  SELECT
    *
  FROM
    `jthomas-billing.billing.aws_billing_v1`
  INNER JOIN
    `jthomas-billing.billing.aws_billing_latest_reports_v1`
  USING
    (billing_assembly_id) ),
  aws_costs AS (
  SELECT
    usage_start_date AS date,
    REGEXP_EXTRACT(resourcetags_user_name, "(.+)/.+") AS provisionerId,
    ifnull(REGEXP_EXTRACT(resourcetags_user_name, ".+/(.+)"),
      resourcetags_user_name) AS workerType,
    "aws" AS cost_origin,
    CASE
      WHEN lineitem_operation LIKE "RunInstances%" THEN "EC2 Instance"
    -- we need to bundle Spot, Reserved and On Demand compute together since we cannot
    -- map workerPoolId/task costs down to this granularity without aggregating costs at
    -- a per instance level
    -- WHEN lineitem_lineitemdescription LIKE "%Spot Instance%" THEN "Spot Instance"
    -- WHEN lineitem_lineitemdescription LIKE "%reserved instance%" THEN "Reserved Instance"
    -- WHEN lineitem_lineitemdescription LIKE "%On Demand%" THEN "On Demand"
      WHEN lineitem_lineitemdescription LIKE "%data transfer%" THEN "Data Transfer"
      WHEN lineitem_lineitemdescription LIKE "%storage%" THEN "Storage"
      WHEN lineitem_lineitemdescription LIKE "%snapshot data%" THEN "Snapshot Data"
      WHEN lineitem_lineitemdescription LIKE "%requests%" THEN "Requests"
      WHEN lineitem_lineitemdescription LIKE "%log storage%" THEN "Log Storage"
      WHEN lineitem_lineitemdescription LIKE "%CloudTrail%" THEN "CloudTrail"
      WHEN lineitem_lineitemdescription LIKE "%log data ingested%" THEN "Log Data Ingested"
      WHEN lineitem_lineitemdescription LIKE "%event recorded%" THEN "Event Recorded"
      WHEN lineitem_lineitemdescription LIKE "%metrics%" THEN "Metrics"
      WHEN lineitem_lineitemdescription LIKE "%VPN%" THEN "VPN"
    ELSE
    "other"
  END
    AS description,
    SUM(lineitem_unblendedcost) AS cost,
    SUM(
    IF
      (lineitem_operation LIKE "RunInstances%"
        AND (pricing_unit = "Hours"
          OR pricing_unit = "Hrs"),
        lineitem_usageamount,
        NULL)) AS hours,
    -- only sum up compute hours all other costs will be divided into this time
    CASE lineitem_usageaccountid
      WHEN 692406183521 THEN "firefox"   -- TaskCluster Platform - 8100
      WHEN 43838267467 THEN "firefox"    -- cloudops-taskcluster-aws-prod
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
    AND usage_start_date >= start_date
    AND usage_start_date < end_date
  GROUP BY
    date,
    provisionerId,
    workerType,
    description,
    cluster),
  aws_hours AS (
  SELECT
    date,
    provisionerId,
    workerType,
    cost,
    hours,
    cost / (hours * 3600 * 1000) AS cost_per_ms,
    cost_origin,
    cluster,
    description
  FROM
    aws_costs
  WHERE
    hours IS NOT NULL ),
  aws AS (
  SELECT
    a.date,
    a.provisionerId,
    a.workerType,
    a.cost,
    CAST(NULL AS float64) AS hours,
    a.cost / (a1.hours * 3600 * 1000) AS cost_per_ms,
    a.cost_origin,
    a.cluster,
    a.description
  FROM
    aws_costs AS a
  LEFT JOIN
    aws_hours AS a1
  ON
    a.date = a1.date
    AND ((a.provisionerId IS NULL
        AND a1.provisionerId IS NULL)
      OR a.provisionerId = a1.provisionerId)
    AND ((a.workerType IS NULL
        AND a1.workerType IS NULL)
      OR a.workerType = a1.workerType)
    AND a.cluster = a1.cluster
  WHERE
    a.hours IS NULL
  UNION ALL
  SELECT
    *
  FROM
    aws_hours),
  /* GCP Cost Calculations */ gcp_costs AS (
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
  IF
    (service.description = "Compute Engine",
      SUM(
      IF
        (usage.unit = "seconds",
          usage.amount,
          NULL)) / 3600,
      NULL) AS hours,
    -- only sum up compute hours all other costs will be divided into this time
    "gcp" AS cost_origin,
    CASE
      WHEN STARTS_WITH(project.id, "fxci-prod") THEN "firefox"
      WHEN STARTS_WITH(project.id, "fxci-stag") THEN "stage"
    ELSE
    REGEXP_EXTRACT(project.id, "([^-]+)")
  END
    AS cluster,
    service.description AS description
  FROM
    `moz-fx-billing-212017.billing.gcp_billing_export_v1_01E7D5_97288E_E2EBA0`
  WHERE
    _PARTITIONTIME >= CAST(start_date AS timestamp)
    AND _PARTITIONTIME < CAST(end_date AS timestamp)
    AND EXTRACT(date
    FROM
      usage_start_time) >= start_date
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
    cluster,
    description),
  gcp_hours AS (
  SELECT
    date,
    provisionerId,
    workerType,
    cost,
    hours,
    cost / (hours * 3600 * 1000) AS cost_per_ms,
    cost_origin,
    cluster,
    description
  FROM
    gcp_costs
  WHERE
    hours IS NOT NULL ),
  gcp AS (
  SELECT
    a.date,
    a.provisionerId,
    a.workerType,
    a.cost,
    CAST(NULL AS float64) AS hours,
    a.cost / (a1.hours * 3600 * 1000) AS cost_per_ms,
    a.cost_origin,
    a.cluster,
    a.description
  FROM
    gcp_costs AS a
  LEFT JOIN
    gcp_hours AS a1
  ON
    a.date = a1.date
    AND ((a.provisionerId IS NULL
        AND a1.provisionerId IS NULL)
      OR a.provisionerId = a1.provisionerId)
    AND ((a.workerType IS NULL
        AND a1.workerType IS NULL)
      OR a.workerType = a1.workerType)
    AND a.cluster = a1.cluster
  WHERE
    a.hours IS NULL
  UNION ALL
  SELECT
    *
  FROM
    gcp_hours) /* Aggregration into the results table */
SELECT
  *
FROM
  relops
UNION ALL
SELECT
  *
FROM
  relops_overhead
UNION ALL
SELECT
  *
FROM
  aws
UNION ALL
SELECT
  *
FROM
  gcp

WITH
  a AS (
  SELECT
    APPROX_QUANTILES(total_seconds, 100 IGNORE NULLS) AS quants
  FROM
    `moz-fx-data-taskclu-prod-8fbf.taskclusteretl.derived_taskgroup_costs`
  WHERE
    project = 'try'
    AND cost IS NOT NULL
    AND tasks > 1 -- Ignore things that are likely only a decision task, due to rate of failures there
    AND date > DATE_SUB(@run_date, INTERVAL 60 day)
    AND 'reviewbot@noreply.mozilla.org' NOT IN UNNEST(owners) )
SELECT
  quant
FROM
  a
CROSS JOIN
  UNNEST(a.quants) AS quant
ORDER BY
  quant ASC

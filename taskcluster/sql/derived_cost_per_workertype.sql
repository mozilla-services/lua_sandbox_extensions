SELECT
  date,
  workerType,
  SUM(cost)/SUM(duration_ms) AS cost_per_ms
FROM
  taskclusteretl.raw_cost
WHERE
  duration_ms > 0
GROUP BY
  date,
  workerType

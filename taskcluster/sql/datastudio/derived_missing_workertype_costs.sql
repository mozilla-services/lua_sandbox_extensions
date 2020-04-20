SELECT
  kinds.provisionerId,
  kinds.workerType,
  COUNT(kinds.workerType) AS task_count
FROM
  `moz-fx-data-taskclu-prod-8fbf.taskclusteretl.derived_kind_costs` AS kinds
LEFT JOIN
  taskclusteretl.derived_daily_cost_per_workertype AS costs
ON
  costs.workerType = kinds.workerType
WHERE
  costs.workerType IS NULL
  AND kinds.cost IS NULL
  AND kinds.date > DATE_SUB(CURRENT_DATE(), INTERVAL 35 day)
  AND kinds.date < DATE_SUB(CURRENT_DATE(), INTERVAL 5 day)
GROUP BY
  provisionerId,
  workerType

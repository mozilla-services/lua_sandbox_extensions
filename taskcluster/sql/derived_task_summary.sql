SELECT
  DISTINCT -- in some use cases there are exact duplicate submissions e.g. exception, canceled
  EXTRACT(date
  FROM
    started) AS date,
  runId,
  state,
  result,
  taskGroupId,
  taskId,
  CASE
    WHEN REGEXP_CONTAINS(workerType, "^test\\-.+\\-a$") THEN "test-generic"
    WHEN REGEXP_CONTAINS(workerType, "^dummy\\-worker\\-") THEN "dummy-worker"
    WHEN REGEXP_CONTAINS(workerType, "^dummy\\-type\\-") THEN "dummy-type"
  ELSE
  workerType
END
  AS workerType,
  created,
  scheduled,
  started,
  resolved,
  owner,
  origin,
  project,
  projectOwner,
  revision,
  pushId,
  kind os,
  platform,
  tier,
  groupSymbol,
  symbol,
  ARRAY_TO_STRING(collection, ",") AS collection,
  logStart,
  logEnd,
  TIMESTAMP_DIFF(started, scheduled, millisecond) / 1000 AS lag,
  TIMESTAMP_DIFF(resolved, started, millisecond) / 1000 AS execution
FROM
  taskclusteretl.timing
WHERE
  level = 0
  AND logStart >= CAST(DATE_SUB(@run_date, INTERVAL 1 day) AS timestamp) -- we have to use the partition column here which is slightly later than 'started'
  AND logStart < CAST(DATE(@run_time) AS timestamp)

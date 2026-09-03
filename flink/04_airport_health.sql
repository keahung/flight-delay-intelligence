-- Anomaly detection on ground congestion, per airport.
-- ML_DETECT_ANOMALIES maintains a rolling baseline per partition, so "normal"
-- is defined by each airport's own recent history -- no external schedule needed.
CREATE TABLE airport_health
WITH ('changelog.mode' = 'append')
AS
SELECT
  airport,
  window_start,
  window_end,
  taxiing_aircraft,
  airborne_aircraft,
  departures,
  avg_taxi_out_min,
  ML_DETECT_ANOMALIES(
    CAST(taxiing_aircraft AS DOUBLE),
    `$rowtime`,
    JSON_OBJECT(
      'minTrainingSize'      VALUE 12,
      'maxTrainingSize'      VALUE 50,
      'confidencePercentage' VALUE 99.0,
      'enableStl'            VALUE FALSE
    )
  ) OVER (
    PARTITION BY airport
    ORDER BY `$rowtime`
    RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS congestion_anomaly
FROM airport_ops_10m;

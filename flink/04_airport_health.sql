-- Statistical layer: establishes what "normal" is per airport so the judgment
-- layer never has to guess a threshold.
--
-- The anomaly detector now runs on DEPARTURES (throughput), which collapses during
-- a ground stop. It previously ran on a count of aircraft in motion, which FELL for
-- the same event -- detecting the phenomenon backwards. queue_ratio is carried
-- alongside as the corroborating signal, since it RISES when throughput falls.
CREATE TABLE airport_health
WITH ('changelog.mode' = 'append')
AS
SELECT
  airport, window_start, window_end, window_time,
  ground_moving, ground_stopped, queue_ratio, airborne_nearby,
  departures, avg_taxi_out_min,
  raw_metar, flt_cat, gdp_reason, gdp_avg_delay_min,
  AVG(CAST(departures AS DOUBLE)) OVER w    AS baseline_departures,
  STDDEV_POP(CAST(departures AS DOUBLE)) OVER w AS stddev_departures,
  AVG(queue_ratio) OVER w                   AS baseline_queue_ratio,
  AVG(avg_taxi_out_min) OVER w              AS baseline_taxi_out_min,
  COUNT(*) OVER w                           AS windows_seen,
  ML_DETECT_ANOMALIES(
    CAST(departures AS DOUBLE),
    window_time,
    JSON_OBJECT(
      'minTrainingSize'      VALUE 12,
      'maxTrainingSize'      VALUE 50,
      'confidencePercentage' VALUE 99.0,
      'enableStl'            VALUE FALSE
    )
  ) OVER w AS throughput_anomaly
FROM airport_context_10m
WINDOW w AS (
  PARTITION BY airport ORDER BY window_time
  RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
);

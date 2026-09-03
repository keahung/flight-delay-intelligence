-- Statistical layer: establishes what "normal" is for each airport, so the
-- judgment layer never has to guess. Adds three things to the context table:
--   baseline_*        rolling per-airport mean (what normal looks like here)
--   windows_seen      baseline maturity, so downstream can decline on thin data
--   congestion_anomaly ML_DETECT_ANOMALIES verdict on ground congestion
CREATE TABLE airport_health
WITH ('changelog.mode' = 'append')
AS
SELECT
  airport, window_start, window_end,
  taxiing_aircraft, airborne_aircraft, departures, avg_taxi_out_min,
  raw_metar, flt_cat, gdp_reason, gdp_avg_delay_min,
  AVG(CAST(taxiing_aircraft AS DOUBLE)) OVER (
    PARTITION BY airport ORDER BY `$rowtime`
    RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS baseline_taxiing,
  AVG(CAST(departures AS DOUBLE)) OVER (
    PARTITION BY airport ORDER BY `$rowtime`
    RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS baseline_departures,
  COUNT(*) OVER (
    PARTITION BY airport ORDER BY `$rowtime`
    RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS windows_seen,
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
    PARTITION BY airport ORDER BY `$rowtime`
    RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS congestion_anomaly
FROM airport_context_10m;

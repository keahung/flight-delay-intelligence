CREATE TABLE airport_context_10m (
  window_start      TIMESTAMP_LTZ(3),
  window_end        TIMESTAMP_LTZ(3),
  window_time       TIMESTAMP_LTZ(3),
  airport           STRING,
  ground_moving     BIGINT,
  ground_stopped    BIGINT,
  airborne_nearby   BIGINT,
  queue_ratio       DOUBLE,
  departures        BIGINT,
  avg_taxi_out_min  DOUBLE,
  raw_metar         STRING,
  flt_cat           STRING,
  gdp_reason        STRING,
  gdp_avg_delay_min STRING,
  WATERMARK FOR window_time AS window_time - INTERVAL '5' SECOND
) WITH ('changelog.mode' = 'append');

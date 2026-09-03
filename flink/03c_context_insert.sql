-- R7 FIX: the previous version chained three window LEFT JOINs. Flink planned them
-- as REGULAR joins (NoUniqueKey), which emit retractions -- silently tolerated by
-- CTAS, rejected outright by an append-only sink. Instead of joining, we UNION the
-- four sources into one event stream tagged by origin and do a SINGLE windowed
-- aggregation with FILTERed aggregates. Append-only by construction, no join state,
-- and no watermark minimum across join inputs.
INSERT INTO airport_context_10m
SELECT
  window_start, window_end, window_time, airport,
  COUNT(DISTINCT hex) FILTER (WHERE src='ac' AND on_ground AND at_field AND gs_kt >  5) AS ground_moving,
  COUNT(DISTINCT hex) FILTER (WHERE src='ac' AND on_ground AND at_field AND gs_kt <= 5) AS ground_stopped,
  COUNT(DISTINCT hex) FILTER (WHERE src='ac' AND NOT on_ground)                         AS airborne_nearby,
  CAST(COUNT(DISTINCT hex) FILTER (WHERE src='ac' AND on_ground AND at_field AND gs_kt <= 5) AS DOUBLE)
    / NULLIF(CAST(COUNT(DISTINCT hex) FILTER (WHERE src='ac' AND on_ground AND at_field) AS DOUBLE), 0) AS queue_ratio,
  COUNT(*) FILTER (WHERE src='dep')                                   AS departures,
  AVG(CAST(taxi_out_sec AS DOUBLE)) FILTER (WHERE src='dep') / 60.0   AS avg_taxi_out_min,
  LAST_VALUE(metar)      FILTER (WHERE src='wx')                      AS raw_metar,
  LAST_VALUE(flt_cat)    FILTER (WHERE src='wx')                      AS flt_cat,
  LAST_VALUE(gdp_reason) FILTER (WHERE src='faa')                     AS gdp_reason,
  LAST_VALUE(gdp_avg)    FILTER (WHERE src='faa')                     AS gdp_avg_delay_min
FROM TABLE(TUMBLE(TABLE airport_events_unified, DESCRIPTOR(event_time), INTERVAL '10' MINUTE))
WHERE airport IN ('ORD','SFO','JFK')
GROUP BY window_start, window_end, window_time, airport;

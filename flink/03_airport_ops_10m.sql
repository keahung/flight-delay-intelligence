-- Windowed operational metrics per airport.
-- Two signals: ground congestion (dense, from every position sample) and
-- departure throughput (sparse, one row per detected wheels-up).
CREATE TABLE airport_ops_10m
WITH ('changelog.mode' = 'append')
AS
SELECT
  a.window_start,
  a.window_end,
  a.window_time,
  a.airport,
  a.taxiing_aircraft,
  a.airborne_aircraft,
  COALESCE(d.departures, 0)            AS departures,
  d.avg_taxi_out_min
FROM (
  SELECT window_start, window_end, window_time, airport,
         COUNT(DISTINCT hex) FILTER (WHERE on_ground AND gs_kt > 5) AS taxiing_aircraft,
         COUNT(DISTINCT hex) FILTER (WHERE NOT on_ground)           AS airborne_aircraft
  FROM TABLE(TUMBLE(
        TABLE aircraft_clean,
        DESCRIPTOR(`$rowtime`), INTERVAL '10' MINUTE))
  GROUP BY window_start, window_end, window_time, airport
) a
LEFT JOIN (
  SELECT window_start, window_end, airport,
         COUNT(*)                                     AS departures,
         AVG(CAST(taxi_out_sec AS DOUBLE)) / 60.0     AS avg_taxi_out_min
  FROM TABLE(TUMBLE(
        TABLE departure_events,
        DESCRIPTOR(`$rowtime`), INTERVAL '10' MINUTE))
  GROUP BY window_start, window_end, airport
) d
  ON a.window_start = d.window_start
 AND a.window_end   = d.window_end
 AND a.airport      = d.airport;

-- 10-minute operational picture per airport, joined with the two CONTEXT sources
-- the judgment layer needs to attribute cause: observed weather and FAA programs.
--
-- R2 FIX: the previous congestion metric counted aircraft with gs > 5 -- aircraft
-- IN MOTION. During a ground stop or a held departure queue (exactly what this
-- project exists to detect) aircraft sit stationary with engines running, so they
-- DROPPED OUT of the count: the signal fell when congestion was worst. We now track
-- both halves and derive queue_ratio, which RISES with congestion, and treat
-- departures (throughput) as the primary signal, which FALLS. All ground metrics
-- are restricted to at_field (R1).
CREATE TABLE airport_context_10m
WITH ('changelog.mode' = 'append')
AS
SELECT
  ops.window_start, ops.window_end, ops.window_time, ops.airport,
  ops.ground_moving, ops.ground_stopped, ops.airborne_nearby,
  CAST(ops.ground_stopped AS DOUBLE)
    / NULLIF(CAST(ops.ground_moving + ops.ground_stopped AS DOUBLE), 0) AS queue_ratio,
  COALESCE(dep.departures, 0) AS departures,
  dep.avg_taxi_out_min,
  wx.raw_metar, wx.flt_cat,
  faa.gdp_reason, faa.gdp_avg_delay_min
FROM (
  SELECT window_start, window_end, window_time, airport,
         COUNT(DISTINCT hex) FILTER (WHERE on_ground AND at_field AND gs_kt >  5) AS ground_moving,
         COUNT(DISTINCT hex) FILTER (WHERE on_ground AND at_field AND gs_kt <= 5) AS ground_stopped,
         COUNT(DISTINCT hex) FILTER (WHERE NOT on_ground)                         AS airborne_nearby
  FROM TABLE(TUMBLE(TABLE aircraft_clean, DESCRIPTOR(`$rowtime`), INTERVAL '10' MINUTE))
  GROUP BY window_start, window_end, window_time, airport
) ops
LEFT JOIN (
  SELECT window_start, window_end, window_time, airport,
         COUNT(*) AS departures,
         AVG(CAST(taxi_out_sec AS DOUBLE)) / 60.0 AS avg_taxi_out_min
  FROM TABLE(TUMBLE(TABLE departure_events, DESCRIPTOR(`$rowtime`), INTERVAL '10' MINUTE))
  GROUP BY window_start, window_end, window_time, airport
) dep
  ON ops.window_start = dep.window_start AND ops.window_end = dep.window_end
 AND ops.airport = dep.airport
LEFT JOIN (
  SELECT window_start, window_end, window_time,
         SUBSTRING(JSON_VALUE(CAST(val AS STRING),'$.icaoId') FROM 2) AS airport,
         LAST_VALUE(JSON_VALUE(CAST(val AS STRING),'$.rawOb'))  AS raw_metar,
         LAST_VALUE(JSON_VALUE(CAST(val AS STRING),'$.fltCat')) AS flt_cat
  FROM TABLE(TUMBLE(TABLE metar_raw, DESCRIPTOR(`$rowtime`), INTERVAL '10' MINUTE))
  GROUP BY window_start, window_end, window_time,
           SUBSTRING(JSON_VALUE(CAST(val AS STRING),'$.icaoId') FROM 2)
) wx
  ON ops.window_start = wx.window_start AND ops.window_end = wx.window_end
 AND ops.airport = wx.airport
LEFT JOIN (
  SELECT window_start, window_end, window_time,
         JSON_VALUE(CAST(val AS STRING),'$.airportId') AS airport,
         LAST_VALUE(JSON_VALUE(CAST(val AS STRING),'$.groundDelay.impactingCondition')) AS gdp_reason,
         LAST_VALUE(JSON_VALUE(CAST(val AS STRING),'$.groundDelay.avgDelay'))           AS gdp_avg_delay_min
  FROM TABLE(TUMBLE(TABLE faa_raw, DESCRIPTOR(`$rowtime`), INTERVAL '10' MINUTE))
  GROUP BY window_start, window_end, window_time,
           JSON_VALUE(CAST(val AS STRING),'$.airportId')
) faa
  ON ops.window_start = faa.window_start AND ops.window_end = faa.window_end
 AND ops.airport = faa.airport;

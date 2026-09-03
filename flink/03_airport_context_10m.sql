-- Joins operational metrics with the two CONTEXT sources the agent needs to
-- attribute cause: observed weather (raw METAR text) and official FAA delay programs.
CREATE TABLE airport_context_10m
WITH ('changelog.mode' = 'append')
AS
SELECT
  ops.window_start, ops.window_end, ops.airport,
  ops.taxiing_aircraft, ops.airborne_aircraft,
  COALESCE(dep.departures, 0) AS departures,
  dep.avg_taxi_out_min,
  wx.raw_metar, wx.flt_cat,
  faa.gdp_reason, faa.gdp_avg_delay_min
FROM (
  SELECT window_start, window_end, airport,
         COUNT(DISTINCT hex) FILTER (WHERE on_ground AND gs_kt > 5) AS taxiing_aircraft,
         COUNT(DISTINCT hex) FILTER (WHERE NOT on_ground)           AS airborne_aircraft
  FROM TABLE(TUMBLE(TABLE aircraft_clean, DESCRIPTOR(`$rowtime`), INTERVAL '10' MINUTE))
  GROUP BY window_start, window_end, airport
) ops
LEFT JOIN (
  SELECT window_start, window_end, airport,
         COUNT(*) AS departures,
         AVG(CAST(taxi_out_sec AS DOUBLE)) / 60.0 AS avg_taxi_out_min
  FROM TABLE(TUMBLE(TABLE departure_events, DESCRIPTOR(`$rowtime`), INTERVAL '10' MINUTE))
  GROUP BY window_start, window_end, airport
) dep
  ON ops.window_start = dep.window_start AND ops.window_end = dep.window_end
 AND ops.airport = dep.airport
LEFT JOIN (
  SELECT window_start, window_end,
         SUBSTRING(JSON_VALUE(CAST(val AS STRING),'$.icaoId') FROM 2) AS airport,
         LAST_VALUE(JSON_VALUE(CAST(val AS STRING),'$.rawOb'))  AS raw_metar,
         LAST_VALUE(JSON_VALUE(CAST(val AS STRING),'$.fltCat')) AS flt_cat
  FROM TABLE(TUMBLE(TABLE metar_raw, DESCRIPTOR(`$rowtime`), INTERVAL '10' MINUTE))
  GROUP BY window_start, window_end,
           SUBSTRING(JSON_VALUE(CAST(val AS STRING),'$.icaoId') FROM 2)
) wx
  ON ops.window_start = wx.window_start AND ops.window_end = wx.window_end
 AND ops.airport = wx.airport
LEFT JOIN (
  SELECT window_start, window_end,
         JSON_VALUE(CAST(val AS STRING),'$.airportId') AS airport,
         LAST_VALUE(JSON_VALUE(CAST(val AS STRING),'$.groundDelay.impactingCondition')) AS gdp_reason,
         LAST_VALUE(JSON_VALUE(CAST(val AS STRING),'$.groundDelay.avgDelay'))           AS gdp_avg_delay_min
  FROM TABLE(TUMBLE(TABLE faa_raw, DESCRIPTOR(`$rowtime`), INTERVAL '10' MINUTE))
  GROUP BY window_start, window_end, JSON_VALUE(CAST(val AS STRING),'$.airportId')
) faa
  ON ops.window_start = faa.window_start AND ops.window_end = faa.window_end
 AND ops.airport = faa.airport;

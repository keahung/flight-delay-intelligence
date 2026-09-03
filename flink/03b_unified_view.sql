-- One event stream, tagged by origin, so the 10-minute picture is a single
-- windowed aggregation rather than three chained joins (see R7).
CREATE VIEW airport_events_unified AS
SELECT airport, event_time, 'ac' AS src, hex, on_ground, at_field, gs_kt,
       CAST(NULL AS INT) AS taxi_out_sec, CAST(NULL AS STRING) AS metar,
       CAST(NULL AS STRING) AS flt_cat, CAST(NULL AS STRING) AS gdp_reason,
       CAST(NULL AS STRING) AS gdp_avg
FROM aircraft_clean
UNION ALL
SELECT airport, wheels_up_time, 'dep', hex, CAST(NULL AS BOOLEAN), CAST(NULL AS BOOLEAN),
       CAST(NULL AS DOUBLE), taxi_out_sec, CAST(NULL AS STRING),
       CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(NULL AS STRING)
FROM departure_events
UNION ALL
SELECT SUBSTRING(JSON_VALUE(CAST(val AS STRING),'$.icaoId') FROM 2), `$rowtime`, 'wx',
       CAST(NULL AS STRING), CAST(NULL AS BOOLEAN), CAST(NULL AS BOOLEAN),
       CAST(NULL AS DOUBLE), CAST(NULL AS INT),
       JSON_VALUE(CAST(val AS STRING),'$.rawOb'),
       JSON_VALUE(CAST(val AS STRING),'$.fltCat'),
       CAST(NULL AS STRING), CAST(NULL AS STRING)
FROM metar_raw
UNION ALL
SELECT JSON_VALUE(CAST(val AS STRING),'$.airportId'), `$rowtime`, 'faa',
       CAST(NULL AS STRING), CAST(NULL AS BOOLEAN), CAST(NULL AS BOOLEAN),
       CAST(NULL AS DOUBLE), CAST(NULL AS INT), CAST(NULL AS STRING), CAST(NULL AS STRING),
       JSON_VALUE(CAST(val AS STRING),'$.groundDelay.impactingCondition'),
       JSON_VALUE(CAST(val AS STRING),'$.groundDelay.avgDelay')
FROM faa_raw;

INSERT INTO aircraft_clean
SELECT * FROM (
  SELECT
    'ORD' AS airport,
    JSON_VALUE(j,'$.hex')                        AS hex,
    TRIM(COALESCE(JSON_VALUE(j,'$.flight'),''))  AS callsign,
    JSON_VALUE(j,'$.r')                          AS tail,
    JSON_VALUE(j,'$.t')                          AS actype,
    JSON_VALUE(j,'$.category')                   AS category,
    (JSON_VALUE(j,'$.alt_baro') = 'ground')      AS on_ground,
    TRY_CAST(JSON_VALUE(j,'$.alt_baro') AS INT)  AS alt_ft,
    JSON_VALUE(j,'$.gs'  RETURNING DOUBLE)       AS gs_kt,
    TRY_CAST(JSON_VALUE(j,'$.baro_rate') AS INT) AS baro_rate,
    JSON_VALUE(j,'$.lat' RETURNING DOUBLE)       AS lat,
    JSON_VALUE(j,'$.lon' RETURNING DOUBLE)       AS lon,
    JSON_VALUE(j,'$.seen' RETURNING DOUBLE)      AS seen_sec,
    (    JSON_VALUE(j,'$.lat' RETURNING DOUBLE) BETWEEN 41.955  AND 42.005
     AND JSON_VALUE(j,'$.lon' RETURNING DOUBLE) BETWEEN -87.940 AND -87.860) AS at_field,
    et AS event_time
  FROM (SELECT CAST(val AS STRING) AS j, `$rowtime` AS et FROM aircraft_raw_ord)
  UNION ALL
  SELECT
    'SFO', JSON_VALUE(j,'$.hex'), TRIM(COALESCE(JSON_VALUE(j,'$.flight'),'')),
    JSON_VALUE(j,'$.r'), JSON_VALUE(j,'$.t'), JSON_VALUE(j,'$.category'),
    (JSON_VALUE(j,'$.alt_baro') = 'ground'), TRY_CAST(JSON_VALUE(j,'$.alt_baro') AS INT),
    JSON_VALUE(j,'$.gs' RETURNING DOUBLE), TRY_CAST(JSON_VALUE(j,'$.baro_rate') AS INT),
    JSON_VALUE(j,'$.lat' RETURNING DOUBLE), JSON_VALUE(j,'$.lon' RETURNING DOUBLE),
    JSON_VALUE(j,'$.seen' RETURNING DOUBLE),
    (    JSON_VALUE(j,'$.lat' RETURNING DOUBLE) BETWEEN 37.600   AND 37.645
     AND JSON_VALUE(j,'$.lon' RETURNING DOUBLE) BETWEEN -122.405 AND -122.355),
    et
  FROM (SELECT CAST(val AS STRING) AS j, `$rowtime` AS et FROM aircraft_raw_sfo)
  UNION ALL
  SELECT
    'JFK', JSON_VALUE(j,'$.hex'), TRIM(COALESCE(JSON_VALUE(j,'$.flight'),'')),
    JSON_VALUE(j,'$.r'), JSON_VALUE(j,'$.t'), JSON_VALUE(j,'$.category'),
    (JSON_VALUE(j,'$.alt_baro') = 'ground'), TRY_CAST(JSON_VALUE(j,'$.alt_baro') AS INT),
    JSON_VALUE(j,'$.gs' RETURNING DOUBLE), TRY_CAST(JSON_VALUE(j,'$.baro_rate') AS INT),
    JSON_VALUE(j,'$.lat' RETURNING DOUBLE), JSON_VALUE(j,'$.lon' RETURNING DOUBLE),
    JSON_VALUE(j,'$.seen' RETURNING DOUBLE),
    (    JSON_VALUE(j,'$.lat' RETURNING DOUBLE) BETWEEN 40.620  AND 40.665
     AND JSON_VALUE(j,'$.lon' RETURNING DOUBLE) BETWEEN -73.825 AND -73.740),
    et
  FROM (SELECT CAST(val AS STRING) AS j, `$rowtime` AS et FROM aircraft_raw_jfk)
)
WHERE hex IS NOT NULL
  AND hex NOT LIKE '~%'
  AND COALESCE(category,'') NOT IN ('C1','C2','C3')
  AND COALESCE(seen_sec, 0) < 60;

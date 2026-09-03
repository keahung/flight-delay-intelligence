INSERT INTO departure_events
SELECT airport, hex, callsign, tail, actype, taxi_start_time, wheels_up_time, taxi_out_sec
FROM (
  SELECT airport, hex, callsign, tail, actype, on_ground, gs_kt, baro_rate, event_time
  FROM aircraft_clean
  WHERE (on_ground = FALSE)
     OR (on_ground = TRUE AND gs_kt > 5 AND at_field)
)
MATCH_RECOGNIZE (
  PARTITION BY hex
  ORDER BY event_time
  MEASURES
    LAST(G.airport)   AS airport,
    LAST(G.callsign)  AS callsign,
    LAST(G.tail)      AS tail,
    LAST(G.actype)    AS actype,
    FIRST(G.event_time) AS taxi_start_time,
    U.event_time        AS wheels_up_time,
    TIMESTAMPDIFF(SECOND, FIRST(G.event_time), U.event_time) AS taxi_out_sec
  ONE ROW PER MATCH
  AFTER MATCH SKIP PAST LAST ROW
  PATTERN (G+ U) WITHIN INTERVAL '45' MINUTE
  DEFINE
    G AS G.on_ground = TRUE,
    U AS U.on_ground = FALSE AND U.baro_rate > 200
);

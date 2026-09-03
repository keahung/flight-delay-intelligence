CREATE TABLE departure_events
WITH ('changelog.mode' = 'append')
AS
SELECT *
FROM (
  SELECT airport, hex, callsign, tail, actype, on_ground, gs_kt, baro_rate,
         `$rowtime` AS rt
  FROM aircraft_clean /*+ OPTIONS('scan.startup.mode'='earliest-offset') */
  WHERE on_ground = FALSE OR (on_ground = TRUE AND gs_kt > 5)
)
MATCH_RECOGNIZE (
  PARTITION BY hex
  ORDER BY rt
  MEASURES
    LAST(G.airport)   AS airport,
    LAST(G.callsign)  AS callsign,
    LAST(G.tail)      AS tail,
    LAST(G.actype)    AS actype,
    FIRST(G.rt)       AS pushback_time,
    U.rt              AS wheels_up_time,
    TIMESTAMPDIFF(SECOND, FIRST(G.rt), U.rt) AS taxi_out_sec
  ONE ROW PER MATCH
  AFTER MATCH SKIP PAST LAST ROW
  PATTERN (G+ U) WITHIN INTERVAL '45' MINUTE
  DEFINE
    G AS G.on_ground = TRUE,
    U AS U.on_ground = FALSE
);

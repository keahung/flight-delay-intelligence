-- Wheels-up detection: an aircraft moving on the airport surface, then airborne.
--
-- Ground rows are restricted to `at_field` (R1) so a Midway pushback can no longer
-- register as an ORD departure. Airborne rows are not, since a climbing aircraft has
-- already left the box. `U` now requires a positive climb rate: a single spurious
-- non-"ground" sample on a parked aircraft would otherwise emit a phantom departure,
-- and departures are the anomaly signal, so phantoms corrupt the metric directly.
CREATE TABLE departure_events
WITH ('changelog.mode' = 'append')
AS
SELECT *
FROM (
  SELECT airport, hex, callsign, tail, actype, on_ground, gs_kt, baro_rate,
         `$rowtime` AS rt
  FROM aircraft_clean
  WHERE (on_ground = FALSE)
     OR (on_ground = TRUE AND gs_kt > 5 AND at_field)
)
MATCH_RECOGNIZE (
  PARTITION BY hex
  ORDER BY rt
  MEASURES
    LAST(G.airport)   AS airport,
    LAST(G.callsign)  AS callsign,
    LAST(G.tail)      AS tail,
    LAST(G.actype)    AS actype,
    FIRST(G.rt)       AS taxi_start_time,
    U.rt              AS wheels_up_time,
    TIMESTAMPDIFF(SECOND, FIRST(G.rt), U.rt) AS taxi_out_sec
  ONE ROW PER MATCH
  AFTER MATCH SKIP PAST LAST ROW
  PATTERN (G+ U) WITHIN INTERVAL '45' MINUTE
  DEFINE
    G AS G.on_ground = TRUE,
    U AS U.on_ground = FALSE AND U.baro_rate > 200
);

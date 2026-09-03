-- R6 FIX: declare event_time explicitly with a WATERMARK instead of relying on the
-- derived table's $rowtime, which is WRITE time. Reprocessing history compressed
-- every derived timestamp into the replay's wall-clock span, collapsing taxi_out_sec
-- to ~0 seconds. The source topics' $rowtime is the connector's write time (within
-- ~15s of observation) and is stable across replays, so it is the correct event time.
CREATE TABLE aircraft_clean (
  airport     STRING,
  hex         STRING,
  callsign    STRING,
  tail        STRING,
  actype      STRING,
  category    STRING,
  on_ground   BOOLEAN,
  alt_ft      INT,
  gs_kt       DOUBLE,
  baro_rate   INT,
  lat         DOUBLE,
  lon         DOUBLE,
  seen_sec    DOUBLE,
  at_field    BOOLEAN,
  event_time  TIMESTAMP_LTZ(3),
  WATERMARK FOR event_time AS event_time - INTERVAL '30' SECOND
) WITH ('changelog.mode' = 'append');

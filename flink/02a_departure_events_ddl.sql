-- wheels_up_time is the event time of a departure, carried from aircraft_clean's
-- watermarked event_time rather than the write timestamp (R6).
CREATE TABLE departure_events (
  airport         STRING,
  hex             STRING,
  callsign        STRING,
  tail            STRING,
  actype          STRING,
  taxi_start_time TIMESTAMP_LTZ(3),
  wheels_up_time  TIMESTAMP_LTZ(3),
  taxi_out_sec    INT,
  WATERMARK FOR wheels_up_time AS wheels_up_time - INTERVAL '1' MINUTE
) WITH ('changelog.mode' = 'append');

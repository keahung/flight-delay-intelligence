-- The judgment layer. Flink has already computed every number; the model's job is
-- causal attribution and a recommendation -- not arithmetic.
CREATE TABLE flight_risk
WITH ('changelog.mode' = 'append')
AS
SELECT
  h.airport,
  h.window_start,
  h.window_end,
  h.taxiing_aircraft,
  h.departures,
  h.avg_taxi_out_min,
  CAST(p.response AS STRING) AS assessment
FROM airport_health h,
LATERAL TABLE(ML_PREDICT('delay_llm',
  CONCAT(
    'You are a flight operations analyst. Using ONLY the measurements below, ',
    'assess departure delay risk. Do not invent numbers.\n\n',
    'Respond in exactly these 4 plain-text lines:\n',
    'Risk: [LOW | ELEVATED | HIGH]\n',
    'Expected departure delay: [minutes, or "nominal"]\n',
    'Likely cause: [one sentence]\n',
    'Advice for a passenger departing in the next 2 hours: [one sentence]\n\n',
    'AIRPORT: ', h.airport, '\n',
    'WINDOW: ', CAST(h.window_start AS STRING), ' to ', CAST(h.window_end AS STRING), ' UTC\n',
    'Aircraft taxiing on the ground: ', CAST(h.taxiing_aircraft AS STRING), '\n',
    'Aircraft airborne in the terminal area: ', CAST(h.airborne_aircraft AS STRING), '\n',
    'Departures (wheels-up) this 10-min window: ', CAST(h.departures AS STRING), '\n',
    'Average taxi-out time: ', COALESCE(CAST(ROUND(h.avg_taxi_out_min,1) AS STRING),'unknown'), ' minutes\n',
    'Note: a high taxiing count with few departures indicates aircraft queueing without departing.'
  ))) AS p;

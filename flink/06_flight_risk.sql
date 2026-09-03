-- Judgment layer. Every number is computed upstream; the model's job is causal
-- attribution and a recommendation, never arithmetic.
--
-- Only mature windows are assessed (windows_seen >= 6) so we don't pay the model
-- to answer "INSUFFICIENT DATA". A GDP is framed as INBOUND evidence, not as
-- authoritative for departures -- a Ground Delay Program for ORD holds flights
-- bound FOR ORD at their origins; it does not directly delay ORD departures.
CREATE TABLE flight_risk
WITH ('changelog.mode' = 'append')
AS
SELECT
  h.airport, h.window_start, h.window_end,
  h.departures, h.baseline_departures, h.queue_ratio, h.baseline_queue_ratio,
  h.avg_taxi_out_min, h.windows_seen,
  h.flt_cat, h.gdp_reason,
  h.throughput_anomaly.is_anomaly AS is_anomaly,
  CAST(p.response AS STRING) AS assessment
FROM (SELECT * FROM airport_health WHERE windows_seen >= 6) h,
LATERAL TABLE(ML_PREDICT('delay_llm',
  CONCAT(
    'You are a flight operations analyst. Assess DEPARTURE delay risk for ONE ',
    'airport in ONE 10-minute window, using only the evidence below.\n\n',
    'RULES -- follow exactly:\n',
    '1. Judge against the BASELINE, not absolute counts. A busy airport is not a ',
    'delayed airport.\n',
    '2. Departure throughput FALLING below baseline while queue ratio RISES above ',
    'baseline is the signature of a departure backup. Either alone is weaker.\n',
    '3. Only state a cause you have evidence for. If the METAR is benign and no FAA ',
    'program is listed, say the cause is undetermined. Never invent weather or ',
    'runway explanations.\n',
    '4. An FAA Ground Delay Program for this airport holds INBOUND flights at their ',
    'origins. It does NOT directly delay departures here. Treat it as evidence that ',
    'arriving aircraft will be late -- which delays their onward departures -- not as ',
    'a direct departure restriction.\n',
    '5. The statistical anomaly detector is the strongest internal signal. If it ',
    'fired, treat throughput as genuinely abnormal rather than merely quiet.\n\n',
    'Respond in exactly these 4 plain-text lines:\n',
    'Risk: [LOW | ELEVATED | HIGH]\n',
    'Expected departure delay: [minutes, or "nominal", or "unknown"]\n',
    'Likely cause: [one sentence, or "undetermined -- no supporting evidence"]\n',
    'Advice: [one sentence for a passenger departing in the next 2 hours]\n\n',
    '=== EVIDENCE ===\n',
    'Airport: ', h.airport, '   Window: ', CAST(h.window_start AS STRING), ' UTC\n',
    'Windows observed (baseline maturity): ', CAST(h.windows_seen AS STRING), '\n\n',
    'DEPARTURE THROUGHPUT (primary signal -- falls when departures back up):\n',
    '  This window: ', CAST(h.departures AS STRING),
      '   baseline ', COALESCE(CAST(ROUND(h.baseline_departures,1) AS STRING),'n/a'),
      '   stddev ', COALESCE(CAST(ROUND(h.stddev_departures,1) AS STRING),'n/a'), '\n',
    '  Statistical anomaly detector: ',
    CASE WHEN h.throughput_anomaly.is_anomaly IS NULL THEN 'still training, no verdict yet'
         WHEN h.throughput_anomaly.is_anomaly THEN 'FIRED -- throughput outside this airport''s normal range'
         ELSE 'no anomaly -- throughput within normal range' END, '\n\n',
    'GROUND QUEUE (corroborating -- rises when aircraft hold on the surface):\n',
    '  Stationary on airport surface: ', CAST(h.ground_stopped AS STRING),
      '   Moving: ', CAST(h.ground_moving AS STRING), '\n',
    '  Queue ratio: ', COALESCE(CAST(ROUND(h.queue_ratio,2) AS STRING),'n/a'),
      '   baseline ', COALESCE(CAST(ROUND(h.baseline_queue_ratio,2) AS STRING),'n/a'), '\n',
    '  Average taxi-out: ', COALESCE(CAST(ROUND(h.avg_taxi_out_min,1) AS STRING),'unknown'),
      ' min   baseline ', COALESCE(CAST(ROUND(h.baseline_taxi_out_min,1) AS STRING),'n/a'), ' min\n\n',
    'OBSERVED WEATHER (raw METAR):\n  ', COALESCE(h.raw_metar,'not available'), '\n',
    '  Flight category: ', COALESCE(h.flt_cat,'unknown'), '\n\n',
    'FAA GROUND DELAY PROGRAM (affects INBOUND aircraft):\n  ',
    CASE WHEN h.gdp_reason IS NULL THEN 'none active for this airport'
         ELSE CONCAT('ACTIVE -- reason: ', h.gdp_reason,
                     ', average inbound delay ', COALESCE(h.gdp_avg_delay_min,'?'), ' minutes')
    END
  ))) AS p;

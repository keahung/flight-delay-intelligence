-- Judgment layer. Every number is already computed upstream; the model's job is
-- causal attribution and a recommendation, never arithmetic.
CREATE TABLE flight_risk
WITH ('changelog.mode' = 'append')
AS
SELECT
  h.airport, h.window_start, h.window_end,
  h.taxiing_aircraft, h.departures, h.avg_taxi_out_min,
  h.baseline_taxiing, h.baseline_departures, h.windows_seen,
  h.flt_cat, h.gdp_reason, h.gdp_avg_delay_min,
  h.congestion_anomaly.is_anomaly AS is_anomaly,
  CAST(p.response AS STRING) AS assessment
FROM airport_health h,
LATERAL TABLE(ML_PREDICT('delay_llm',
  CONCAT(
    'You are a flight operations analyst. Assess departure delay risk for ONE airport ',
    'in ONE 10-minute window, using only the evidence below.\n\n',
    'RULES -- follow exactly:\n',
    '1. If windows_seen < 6, respond ONLY with "Risk: INSUFFICIENT DATA" and one line ',
    'saying the baseline is not yet established. Do not guess.\n',
    '2. Judge against the BASELINE, not absolute counts. A busy airport is not a delayed airport.\n',
    '3. Only state a cause you have evidence for. If the METAR is benign and no FAA ground ',
    'delay program is listed, say the cause is undetermined. Never invent weather or ',
    'runway explanations.\n',
    '4. If an FAA ground delay program IS listed, that is authoritative -- lead with it.\n',
    '5. The statistical anomaly detector is the strongest internal signal. If it fired, ',
    'treat congestion as genuinely abnormal rather than merely busy.\n\n',
    'Respond in exactly these 4 plain-text lines:\n',
    'Risk: [INSUFFICIENT DATA | LOW | ELEVATED | HIGH]\n',
    'Expected departure delay: [minutes, or "nominal", or "unknown"]\n',
    'Likely cause: [one sentence, or "undetermined -- no supporting evidence"]\n',
    'Advice: [one sentence for a passenger departing in the next 2 hours]\n\n',
    '=== EVIDENCE ===\n',
    'Airport: ', h.airport, '   Window: ', CAST(h.window_start AS STRING), ' UTC\n',
    'Windows observed so far (baseline maturity): ', CAST(h.windows_seen AS STRING), '\n\n',
    'THIS WINDOW vs BASELINE:\n',
    '  Aircraft taxiing:  ', CAST(h.taxiing_aircraft AS STRING),
        '   (baseline ', COALESCE(CAST(ROUND(h.baseline_taxiing,1) AS STRING),'n/a'), ')\n',
    '  Wheels-up departures: ', CAST(h.departures AS STRING),
        '   (baseline ', COALESCE(CAST(ROUND(h.baseline_departures,1) AS STRING),'n/a'), ')\n',
    '  Average taxi-out: ', COALESCE(CAST(ROUND(h.avg_taxi_out_min,1) AS STRING),'unknown'), ' min\n',
    '  Statistical anomaly detector: ',
    CASE WHEN h.congestion_anomaly.is_anomaly IS NULL THEN 'still training, no verdict yet'
         WHEN h.congestion_anomaly.is_anomaly THEN 'FIRED -- congestion is outside this airport''s normal range'
         ELSE 'no anomaly -- congestion within normal range' END, '\n\n',
    'OBSERVED WEATHER (raw METAR):\n  ', COALESCE(h.raw_metar, 'not available'), '\n',
    '  Flight category: ', COALESCE(h.flt_cat, 'unknown'), '\n\n',
    'FAA GROUND DELAY PROGRAM:\n  ',
    CASE WHEN h.gdp_reason IS NULL
         THEN 'none active for this airport'
         ELSE CONCAT('ACTIVE -- reason: ', h.gdp_reason,
                     ', average delay ', COALESCE(h.gdp_avg_delay_min,'?'), ' minutes')
    END
  ))) AS p;

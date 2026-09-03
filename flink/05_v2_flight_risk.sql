-- v2 of the judgment layer. Fixes the four defects in v1:
--   1. supplies a rolling per-airport BASELINE so "abnormal" is measurable, not guessed
--   2. supplies windows_seen so the model can decline on immature data
--   3. supplies raw METAR + FAA ground-delay status so cause is evidenced, not invented
--   4. explicitly forbids attributing cause without supporting evidence
CREATE TABLE flight_risk_v2
WITH ('changelog.mode' = 'append')
AS
SELECT
  c.airport, c.window_start, c.window_end,
  c.taxiing_aircraft, c.departures, c.avg_taxi_out_min,
  c.baseline_taxiing, c.baseline_departures, c.windows_seen,
  c.flt_cat, c.gdp_reason, c.gdp_avg_delay_min,
  CAST(p.response AS STRING) AS assessment
FROM (
  SELECT *,
    AVG(CAST(taxiing_aircraft AS DOUBLE)) OVER (
      PARTITION BY airport ORDER BY `$rowtime`
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS baseline_taxiing,
    AVG(CAST(departures AS DOUBLE)) OVER (
      PARTITION BY airport ORDER BY `$rowtime`
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS baseline_departures,
    COUNT(*) OVER (
      PARTITION BY airport ORDER BY `$rowtime`
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS windows_seen
  FROM airport_context_10m
) c,
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
    '4. If an FAA ground delay program IS listed, that is authoritative -- lead with it.\n\n',
    'Respond in exactly these 4 plain-text lines:\n',
    'Risk: [INSUFFICIENT DATA | LOW | ELEVATED | HIGH]\n',
    'Expected departure delay: [minutes, or "nominal", or "unknown"]\n',
    'Likely cause: [one sentence, or "undetermined -- no supporting evidence"]\n',
    'Advice: [one sentence for a passenger departing in the next 2 hours]\n\n',
    '=== EVIDENCE ===\n',
    'Airport: ', c.airport, '   Window: ', CAST(c.window_start AS STRING), ' UTC\n',
    'Windows observed so far (baseline maturity): ', CAST(c.windows_seen AS STRING), '\n\n',
    'THIS WINDOW vs BASELINE:\n',
    '  Aircraft taxiing:  ', CAST(c.taxiing_aircraft AS STRING),
        '   (baseline ', COALESCE(CAST(ROUND(c.baseline_taxiing,1) AS STRING),'n/a'), ')\n',
    '  Wheels-up departures: ', CAST(c.departures AS STRING),
        '   (baseline ', COALESCE(CAST(ROUND(c.baseline_departures,1) AS STRING),'n/a'), ')\n',
    '  Average taxi-out: ', COALESCE(CAST(ROUND(c.avg_taxi_out_min,1) AS STRING),'unknown'), ' min\n\n',
    'OBSERVED WEATHER (raw METAR):\n  ', COALESCE(c.raw_metar, 'not available'), '\n',
    '  Flight category: ', COALESCE(c.flt_cat, 'unknown'), '\n\n',
    'FAA GROUND DELAY PROGRAM:\n  ',
    CASE WHEN c.gdp_reason IS NULL
         THEN 'none active for this airport'
         ELSE CONCAT('ACTIVE -- reason: ', c.gdp_reason,
                     ', average delay ', COALESCE(c.gdp_avg_delay_min,'?'), ' minutes')
    END
  ))) AS p;

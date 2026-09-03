# Independent SQL review — findings

An independent reviewer read the Flink SQL cold, knowing only the goal and the
input data. Findings below, with status. Several invalidate the core metric and
must be fixed before the pipeline's numbers mean anything.

## Status

- **R1 FIXED and verified** — per-airport bounding box. Ground-moving samples are
  now 100% at their labelled airport (ORD was 82%, with 11% DPA and 7% MDW).
- **R2 FIXED** — congestion now tracked as `ground_moving` + `ground_stopped` with a
  derived `queue_ratio` that RISES with congestion; the anomaly detector was moved
  onto `departures` (throughput), which falls during a backup.
- **R8 FIXED and confirmed real** — the 4-way join stalled exactly as predicted, on
  the sparse `departure_events` input rather than `faa_raw`. Setting
  `sql.tables.scan.idle-timeout = 60 s` unblocked it.
- **R6 FIXED and verified** — derived tables now declare an explicit `event_time`
  (or `wheels_up_time`) column with a `WATERMARK` and are populated by `INSERT INTO`
  rather than `CREATE TABLE AS`. Taxi-out went from 0-3 seconds to a realistic
  0.2-18.1 min spread, with wheels-up timestamps preserved at their original times
  during replay. This restores the README's replay guarantee.
- **R7 FIXED and confirmed real** — the chained window LEFT JOINs were in fact
  planning as REGULAR joins; the append-only sink rejected them outright
  ("doesn't support consuming update and delete changes"), which CTAS had been
  hiding. Replaced by a UNION view + a single windowed aggregation with FILTERed
  aggregates: append-only by construction, no join state, no watermark minimum.
- ~~**R6 was escalated to blocking**~~ — no longer theoretical. Rebuilding `aircraft_clean`
  reprocessed 80k records in minutes, collapsing every derived `$rowtime` into that
  wall-clock span. Observed result: `taxi_out_sec` of 0-3 seconds and every wheels-up
  timestamped within the same 10 seconds. All time-based output is currently wrong.
  **Fix next:** declare the derived tables explicitly with an `event_time` column and
  a `WATERMARK`, `INSERT INTO` them, and window on `event_time` rather than `$rowtime`.
- Also applied from "Smaller": `seen_sec < 60` staleness guard, surface-vehicle
  filter (`category` C1-C3), climb confirmation on wheels-up (`baro_rate > 200`),
  `windows_seen >= 6` filter before the LLM call, and the GDP-is-inbound reframing (R4).

## Original findings

## Blocking — the metric does not measure what it claims

### R1. "Airport" is a 25 nm circle containing several other airports
`01_aircraft_clean.sql` labels every aircraft in a topic `'ORD'`/`'SFO'`/`'JFK'`,
but the connectors query a 25 nm radius. **Verified against live data: only 82% of
ground-moving traffic labelled ORD is at ORD — 11% is DuPage (DPA), 7% is Midway
(MDW).** JFK's circle contains LGA and EWR; SFO's contains OAK and HWD. The
headline claim — deviation from *an airport's own* normal — is currently a
metro-area aggregate whose composition shifts hour to hour.
**Fix:** per-airport lat/lon bounding box on ground samples. `dst_nm` is parsed and
unused, and cannot separate ORD from MDW anyway.

### R2. `taxiing_aircraft` moves the *wrong way* during a ground stop
`COUNT(DISTINCT hex) FILTER (WHERE on_ground AND gs_kt > 5)` counts aircraft *in
motion*. During a ground stop or a held departure queue — the exact phenomenon
this project exists to detect — aircraft are **stationary**, so they drop out of
the count. The signal falls when congestion is worst. It also conflates traffic
volume, taxi duration, and sampling coverage.
**Fix:** count ground aircraft with `gs_kt <= 5` away from gates, or use the
taxi-out distribution, which actually carries delay.

### R3. `taxi_out_sec` absorbs the previous arrival's taxi-in, and saturates at 45 min
The `gs_kt > 5` pre-filter deletes parked-at-gate samples, so an aircraft's taxi-in
rows and its later taxi-out rows become adjacent in the per-`hex` sequence with
nothing separating them. Land 12:00, taxi in to 12:10, push back 12:35, wheels-up
12:50 reports `taxi_out_sec` = 2700 instead of 900. Any turnaround under ~45 min is
inflated. Separately, `WITHIN INTERVAL '45' MINUTE` caps the measurement, so a
75-minute deicing taxi and a 46-minute taxi are indistinguishable — the metric
flattens exactly when the delay is worst.

## Significant

### R4. FAA Ground Delay Programs are the wrong product for *departure* delay
A GDP **for ORD** holds flights *inbound to* ORD at their origin airports; it does
not delay departures out of ORD. `06_flight_risk.sql` instructs the model to treat
it as "authoritative" for a departure question. A GDP is real *indirect* evidence
(inbound aircraft arrive late — the project's own thesis) but must be framed that
way. The correct authoritative products are departure Ground Stops, Departure
Delays, Airport Closures, and EDCTs — `03` reads only `$.groundDelay` and discards
every other event type in the same payload.

### R5. Baseline has no time-of-day term and no dispersion
`ROWS/RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` is the mean over every
window since job start. ORD taxiing counts swing ~5x between the 03:00 lull and the
17:00 bank, so the baseline converges to the 24-hour average and every bank reads
"far above baseline" on a perfectly normal day. Only a mean is supplied — no
stddev — so the model must still invent a threshold, which is what the baseline was
meant to remove. Minor: self-inclusion shrinks deviations by (n-1)/n, which is 17%
at the `windows_seen >= 6` gate where the first real verdict is emitted.

### R6. Derived `$rowtime` is write time, not source event time
`01` derives `event_time` and nothing ever reads it; every window and OVER clause
uses the *derived* table's `$rowtime`, assigned at produce time. Live skew is
sub-second so results are approximately right, but on replay everything collapses
into whatever wall-clock windows the replay occupies. **This contradicts the
README's replay claim** — either propagate the source timestamp with a declared
watermark, or drop the claim.

### R7. Window joins may be planning as regular joins
Flink plans a window join only when both inputs carry propagated window
attributes, which requires selecting `window_time`. `03`'s subqueries do not. If
these are regular joins they emit a premature `(row, NULL)` then a retraction —
indistinguishable from a genuine zero-departure window under `COALESCE(...,0)` —
retain unbounded state, and violate `changelog.mode = 'append'`. Note
`scripts/flink.py` discards retractions, so this is invisible via the deploy script.

### R8. Idle `faa_raw` can stall the pipeline
`faa_raw` emits nothing when no airport has an active event — the normal state most
of the day. With a regular join the output watermark is the min across inputs, so
it can freeze and produce **no assessments precisely because nothing is wrong**.
Confirm source idle-timeout covers this.

## Smaller

- `ML_DETECT_ANOMALIES` with `enableStl = FALSE` and `maxTrainingSize = 50`
  (~8.3 h) trains on less than one diurnal period, so every morning ramp is an
  anomaly. Also verify the `OVER` call form against the current PTF signature.
- `seen` is parsed but unused — no staleness guard, so ghost aircraft keep counting.
- `category` is whitelisted but never parsed. C1–C3 are **surface vehicles** (tugs,
  fire, ops) which broadcast real hexes, pass the `~` filter, and move >5 kt on the
  ground — counted as taxiing aircraft.
- `ML_PREDICT` fires even when `windows_seen < 6`; the model is paid to answer
  "INSUFFICIENT DATA". Filter before the lateral join.
- `LAST_VALUE` without ordering is arrival-order dependent — harmless for METAR,
  nondeterministic for a GDP starting or cancelling mid-window.
- `${ANTHROPIC_API_KEY}` in `00_connection.sql` is never substituted; the README's
  `"$(cat ...)"` invocation does not expand it and sends the literal string.

## Confirmed correct

Three-valued `on_ground` handling is consistent across all consumers; `TRY_CAST` on
polymorphic `alt_baro` correctly yields NULL for `"ground"`; the `hex NOT LIKE '~%'`
TIS-B filter is right; `SUBSTRING(icaoId FROM 2)` correctly maps `KORD`→`ORD`; GDP
null-detection is sound; a pure arrival cannot be miscounted as a departure.

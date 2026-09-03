# Flight Delay Intelligence

Predict flight departure delays from **live aircraft telemetry**, before the airline or the
FAA announces them — built on Confluent Cloud (Kafka + Flink + Streaming Agents).

## The premise

Late-arriving aircraft is one of the largest single causes of departure delay in US DOT's
own taxonomy. Your flight is late because the airframe that flies it is still somewhere
else, or because the airport it departs from has quietly stopped moving planes. Both are
observable in real time from public ADS-B data — minutes before any official announcement.

**The question we answer:** *"I'm on UA328 out of ORD at 18:40. Am I going to be late, by
how much, and why?"*

## Architecture

```
SOURCES (all free, no auth)              CONFLUENT CLOUD
─────────────────────────────            ───────────────────────────────────────
api.adsb.lol       poll 15s  ──▶ HTTP Source V1 ──▶ aircraft_raw_{ord,sfo,jfk}
  3 bounding boxes                 + SMT chain           │
aviationweather.gov poll 60s ──▶ HTTP Source V1 ──▶ metar_raw
nasstatus.faa.gov   poll 60s ──▶ HTTP Source V1 ──▶ faa_raw
                                                        │
                                          FLINK SQL     ▼
                                   01  aircraft_clean        parse + type + union
                                   02  departure_events      MATCH_RECOGNIZE wheels-up
                                   03  airport_throughput_10m  TUMBLE 10 min
                                   04  airport_health        ML_DETECT_ANOMALIES
                                   05  flight_risk           CREATE AGENT + AI_RUN_AGENT
```

## Why HTTP Source **V1**, not V2

This is the single most important implementation note.

ADS-B records are *sparse and polymorphic*: `alt_baro` is an integer when a plane is
airborne and the literal string `"ground"` when it is taxiing, and the field set varies by
aircraft equipment and flight phase. Comparing the auto-registered schema against real data
turned up **11 conflicting fields**.

HTTP Source **V2** only emits Schema-Registry formats and infers a schema from the first
record it sees. It rejects `"ground"` as an *"intolerable type conflict"*, and the fix it
suggests (`behavior.on.error`) **drops those records** — silently deleting exactly the
taxiing aircraft the taxi-out metric is computed from.

HTTP Source **V1** with `output.data.format=JSON` is schemaless and keeps everything, while
still exploding arrays via `http.response.data.json.pointer` (`/ac`). Two SMTs make the data
uniform:

| SMT | Purpose |
|---|---|
| `ReplaceField$Value` (include) | whitelist 21 stable fields, drop sparse ones (`ias`, `nav_modes`, `true_heading`…) |
| `Cast$Value` `alt_baro:string` | force one type: `"ground"` \| `"22250"` |

With the SMT chain the connector stops registering a schema, so Flink sees
`key BYTES, val BYTES` and we parse with `JSON_VALUE` — full control over casting, and no
inferred schema can break the pipeline.

Other gotchas: V2 requires `tasks.max == apis.num` (it fails silently otherwise); V1
requires `http.initial.offset=0` under `SIMPLE_INCREMENTING`.

## Data sources

| Topic | Source | Cadence | Role |
|---|---|---|---|
| `aircraft_raw_*` | `api.adsb.lol/v2/lat/../lon/../dist/25` | 15 s | positions, tail #, ground/air state |
| `metar_raw` | `aviationweather.gov/api/data/metar` | 60 s | ceiling, visibility, `fltCat`, raw METAR text |
| `faa_raw` | `nasstatus.faa.gov/api/airport-events` | 60 s | official ground delay programs (**validation**) |

Use `nasstatus.faa.gov/api/airport-events` (JSON, numeric `avgDelay`) rather than
`/api/airport-status-information` (XML, prose: `"2 hours and 16 minutes"`).

Airports: **ORD** (convective), **SFO** (marine-layer ceilings), **JFK** (volume) — three
distinct delay mechanisms requiring three different recommendations.

## Setup

```bash
cp .env.example .env      # fill in Confluent + Anthropic credentials
python3 scripts/deploy_connectors.py           # create the 5 source connectors
python3 scripts/flink.py "$(cat flink/01_aircraft_clean.sql)"
python3 scripts/flink.py "$(cat flink/02_departure_events.sql)"
```

## Capture and replay

Flink windows are **event-time**, so replaying captured records with their original
timestamps produces identical windowed results — just fast. `ML_DETECT_ANOMALIES` needs
`minTrainingSize` windows before it will call anything: at 10-minute windows that is two
hours of wall clock, or about a minute on replay.

Replay needs no connectors — re-run the statements with
`/*+ OPTIONS('scan.startup.mode'='earliest-offset') */`.

## License

MIT

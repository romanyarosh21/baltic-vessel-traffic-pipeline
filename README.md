# Baltic Vessel Traffic Pipeline

Incremental, idempotent ELT pipeline for open Danish AIS vessel-tracking data (about 600 MB per day compressed). Built with Python, PostgreSQL/PostGIS and dbt, with data-quality tests, orchestration and CI. Fully reproducible with Docker Compose.

## Problem

Most ship traffic entering the Baltic Sea passes through the Danish straits. Raw AIS position data describing that traffic is published as large daily files, which are hard to analyse directly: they mix dynamic and static fields, contain noisy coordinates and duplicates, and are too big to open in a spreadsheet.

This project turns those raw files into a clean, tested, queryable dataset.

## Target use cases

- Logistics and freight forwarders: monitor traffic density in the straits.
- Port analysis: measure how long vessels stay at anchor and at berth.
- Maritime safety analysis: detect vessels with long gaps in AIS signal.

## Questions the pipeline will answer

1. How many vessels pass through the straits per day, by vessel type?
2. What is the average dwell time in Danish ports?
3. Which vessels have AIS signal gaps longer than a set threshold?
4. How does traffic change by week and season?

## Data source

Historical AIS data published as daily CSV archives at aisdata.ais.dk. Raw data is not stored in this repository. Check the source's terms of use before redistributing any data.

## Planned architecture

Raw CSV files, loaded by Python into PostgreSQL/PostGIS (raw schema), transformed by dbt (staging and marts), orchestrated and tested in CI, exposed through a dashboard.

## Quick start

Requirements: Docker Desktop and Git.

```
git clone https://github.com/romanyarosh21/baltic-vessel-traffic-pipeline.git
cd baltic-vessel-traffic-pipeline
copy .env.example .env
```

Open `.env` and set a password in `POSTGRES_PASSWORD`. Then start the database:

```
docker compose up -d
```

Check that the schemas were created:

```
docker compose exec db psql -U ais -d ais -c "\dn"
```

Expected schemas: `raw`, `staging`, `marts`.

## Loading a day of data

Download a daily archive from aisdata.ais.dk and unzip it outside the repository. Then install the dependencies and run the loader (Windows PowerShell):

```
python -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python load\load_ais.py "C:\path\to\aisdk-2026-10-21.csv"
```

Add `--limit 100000` to load only the first rows when testing. Running the loader again for the same file replaces that file's rows, so no duplicates are created.

SQL scripts in `sql/` run automatically only when the database is created for the first time. To apply a new script to an existing database:

```
Get-Content sql\02_raw_ais.sql -Raw | docker compose exec -T db psql -U ais -d ais
```

## Loading many days

The loader also accepts a `.zip` archive (no need to unzip) or a folder with daily files:

```
python load\load_ais.py "C:\path\to\folder-with-daily-zips"
```

`raw.load_log` records every finished file, so a file that is already `complete` is skipped on the next run. Use `--force` to reload a file. A run with `--limit` is recorded as `partial`, and that file is loaded again next time. Each file is loaded in its own transaction together with its log entry.

Apply `sql/03_load_log.sql` to an existing database the same way as other new scripts:

```
Get-Content sql\03_load_log.sql -Raw | docker compose exec -T db psql -U ais -d ais
```

First multi-day load: 7 days (2026-10-15 to 2026-10-21), about 117 million raw rows. For every file, `rows_loaded` in the log was compared with the row count in the table.

## Data notes and limitations

- First load: one full day (2026-10-21) produced about 16.5 million raw messages from roughly 2,400 distinct Class A MMSI numbers.
- One MMSI is not guaranteed to be one vessel. Invalid or duplicated numbers are expected and will be filtered in the staging layer.
- The Danish Maritime Authority publishes the data as is, does not guarantee its accuracy, and it must not be used for navigation.
- Data older than 24 months is available only for a limited time, so source files should be kept locally.
- Class B transponders are often privately owned. Results are published as aggregates only, and no attempt is made to identify individuals.

## Staging layer: cleaning rules

`staging.stg_ais_positions` is built by dbt from `raw.ais_messages`. The rules below come from profiling the first loaded day (2026-10-21). The profiling queries are in `dbt/analyses/`.

| Rule | Why | Effect on the 2026-10-21 file |
|---|---|---|
| Keep Class A and Class B only | Base stations, aids to navigation and rescue devices are not vessels | 1,285,448 of 16,515,558 raw rows dropped |
| Drop MMSI that are not exactly 9 digits | Short numbers such as `3638` and `2190045` are not valid vessel identifiers | 68,494 rows |
| Drop the AIS "no position" placeholder (latitude 91, longitude 0) | It marks a missing position, not a location | 31,496 rows |
| Cast timestamps and numbers to proper types | `raw` keeps everything as text | invalid numbers become NULL, never an error |
| Treat `Unknown` and `Undefined` as NULL | They mean "no data" | |
| Deduplicate on (`mmsi`, `message_ts`) | The same message appears several times | about 5.4 million surplus rows |

Counts for the middle rules were measured separately on the raw vessel rows, so they can overlap. Result: 9,750,908 rows from 2,380 Class A and 1,478 Class B distinct MMSI numbers.

### Duplicates: a known trade-off

Among vessel rows, 4,037,126 (`mmsi`, timestamp) pairs occur more than once, 5,436,017 surplus rows in total (about 36% of vessel rows). For 99.3% of these pairs (4,008,398) every copy has the same position, so keeping one row loses nothing. For the other 28,728 pairs (0.7%) the copies disagree on position. The model keeps one of them using a deterministic but arbitrary rule (lowest latitude, then longitude). This is a simplification, not a judgement about which position is correct. Timestamps have one-second resolution, so two genuine messages from one vessel within the same second would also collapse into one row. Why the conflicting copies exist has not been investigated yet.

### Known gaps

- AIS special codes in speed, course and heading (for example "not available" values) are not converted to NULL yet and need review.
- Class B vessels are kept and marked in `vessel_class`. Published results use aggregates only.
- Only one day has been profiled. The rules may need to change when more days are loaded.

### Incremental runs

`stg_ais_positions` is incremental by file. On every run dbt first asks `raw.load_log` which files are complete and either new or reloaded since they were last processed, and then processes only those files. The list is resolved before the main query so that PostgreSQL reads just those files instead of scanning the whole raw table.

- The first run, or any change to the model's columns, needs `dbt run --full-refresh --select stg_ais_positions`.
- Measured on the first eight days: the full rebuild of seven days (68.8 million rows) took about 15.6 minutes, and adding one new day took about 4.8 minutes.
- Reloading a day with `--force` replaces that file's rows in staging on the next run, because its load time in the log becomes newer than the processed copy.
- Do not run the loader and dbt at the same time.
- The database container is started with `shm_size: 1gb`. The default 64 MB made large parallel queries fail with "could not resize shared memory segment".

### Data-quality tests

Eight dbt tests run on the staging model and all pass: `not_null` on `mmsi`, `message_ts`, `latitude`, `longitude` and `vessel_class`, `accepted_values` for `vessel_class`, uniqueness of (`mmsi`, `message_ts`), and a range and format check on coordinates and MMSI.

To run dbt, first load the variables from `.env` into the PowerShell session, then run the model and the tests:

```
Get-Content .env | ForEach-Object { if ($_ -match '^\s*([^#=\s][^=]*)=(.*)$') { Set-Item -Path "env:$($Matches[1].Trim())" -Value $Matches[2].Trim() } }
dbt run --project-dir dbt --profiles-dir dbt
dbt test --project-dir dbt --profiles-dir dbt
```

## Marts layer

| Model | Grain | Purpose |
|---|---|---|
| `marts.dim_vessels` | one row per MMSI | latest known name, type and size, first and last time seen |
| `marts.fct_vessels_daily` | day x vessel class x ship type | distinct vessels and messages per day (question 1) |
| `marts.fct_signal_gaps` | one row per pause over 60 minutes (Class A) | question 3; the threshold is the dbt variable `signal_gap_minutes` |

First result on 8 days (2026-10-15 to 2026-10-22): between 2,076 and 2,735 distinct Class A vessels per day and between 1,419 and 1,855 Class B. The Class B count falls over the period; eight days are too few to say whether this is seasonal. About 87% of the 7,176 vessels have a known ship type, the rest are reported as `Unknown`.

Name, type and size come from the latest message that carries them, so a vessel has one ship type for the whole period. All marts models are rebuilt from staging on every `dbt run`; they are not incremental yet. Twenty-three data tests cover staging and marts, including a check that the daily table neither loses nor duplicates messages.

### Signal gaps (question 3)

On the 8 loaded days the model found 13,669 pauses longer than 60 minutes between two consecutive messages of the same Class A vessel. The threshold comes from profiling one day: the median pause is 10 seconds, 99% of pauses are under 3 minutes, and a 10-minute threshold gives about 6,900 pauses a day, mostly noise. By straight-line distance between the last message before and the first message after a pause: 54% under 1 km, 23% between 1 and 20 km, 19% between 20 and 100 km, 4% over 100 km.

A gap means the receivers got nothing, not that a vessel switched AIS off: it may have been moored with a weak signal or have left the coverage area. The model records the evidence (positions, status before the gap, distance) and does not label intent.

## Status

- [x] Repository structure
- [x] PostgreSQL/PostGIS in Docker Compose
- [x] Raw landing table (raw.ais_messages)
- [x] Idempotent per-file loader
- [x] Multi-day loading with a load log (raw layer)
- [x] dbt staging model and data-quality tests
- [x] Incremental staging model
- [x] dbt marts: vessel dimension and daily vessel counts (question 1)
- [ ] dbt marts: port dwell time (question 2)
- [x] dbt marts: AIS signal gaps (question 3)
- [ ] dbt marts: weekly and seasonal trends (question 4)
- [ ] Orchestration
- [ ] CI
- [ ] Dashboard
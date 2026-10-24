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
## Status

- [x] Repository structure
- [x] PostgreSQL/PostGIS in Docker Compose
- [ ] Incremental, idempotent loader
- [ ] dbt models and data-quality tests
- [ ] Orchestration
- [ ] CI
- [ ] Dashboard
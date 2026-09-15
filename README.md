# dbt + Snowflake Bootcamp

A learning project: dbt Core connected to Snowflake, with a seed → source → staging model → tests pipeline. Built as a one-day, hands-on refresher on dbt fundamentals plus git-based CI/CD.

## What this does

1. A small customer dataset is loaded into Snowflake as a **seed**.
2. That seed is declared as a **source**, with freshness checks configured.
3. A **staging model** (`stg_customers`) cleans and renames columns from the source.
4. **Generic tests** (`unique`, `not_null`) validate the staging model's data quality.

## Architecture

```
seeds/raw_customers.csv --(dbt seed)--> Snowflake table
                                              |
                                    (declared as a source)
                                              v
                              models/staging/stg_customers.sql
                                              |
                                        (dbt test)
                                              v
                                   unique / not_null checks
```

- **Snowflake** — data warehouse. Connection uses **key-pair authentication** (not password), since this Snowflake account requires MFA, which isn't compatible with plain password auth for programmatic tools like dbt. This also means the same auth method will work unchanged in CI (GitHub Actions) later.
- **dbt Core** — installed into an isolated **conda environment** (`dbt_bootcamp`), not the system Python. `dbt-snowflake` is the adapter.
- **Seed** (`seeds/raw_customers.csv`) — small static data loaded directly into Snowflake via `dbt seed`, standing in for "raw data" for this learning exercise.
- **Source** (`models/staging/_sources.yml`) — declares the seed's resulting table to dbt as an upstream dependency, including **freshness** thresholds (warn after 7 days stale, error after 14).
- **Staging model** (`models/staging/stg_customers.sql`) — the first transformation layer; renames/cleans columns, referenced via `{{ source('raw', 'raw_customers') }}`.
- **Tests** (`models/staging/_models.yml`) — generic dbt tests (`unique`, `not_null`) on the staging model's key columns.

## Project structure

```
.
├── learn/                          # dbt project root
│   ├── dbt_project.yml               # project config, points at profile "learn"
│   ├── models/
│   │   └── staging/
│   │       ├── stg_customers.sql       # staging model
│   │       ├── _sources.yml            # source declaration + freshness config
│   │       └── _models.yml             # model documentation + tests
│   ├── seeds/
│   │   └── raw_customers.csv           # seed data (stand-in raw data)
│   ├── analyses/, macros/, snapshots/, tests/   # scaffolded, not yet used
│   └── requirements.txt              # pinned Python package versions
└── README.md
```

## Prerequisites

- A Snowflake account (warehouse, database `dbt_bootcamp`, schema `dbt_amiyo` created)
- Snowflake user configured for **key-pair auth**: an RSA key pair generated locally, public key registered on the Snowflake user via `ALTER USER <user> SET RSA_PUBLIC_KEY='...'`
- conda (or another Python env manager) installed locally
- A `~/.dbt/profiles.yml` entry named `learn` pointing at the private key path (see `dbt_project.yml`'s `profile:` field) — **this file is never committed**, it lives outside the repo

## Running this yourself

**Set up the environment:**
```bash
conda create -n dbt_bootcamp python=3.10 -y
conda activate dbt_bootcamp
pip install -r learn/requirements.txt
```

**Verify the Snowflake connection:**
```bash
cd learn
dbt debug
```

**Load seed data and build models:**
```bash
dbt seed
dbt run
```

**Run data quality tests:**
```bash
dbt test
```

**Check source freshness:**
```bash
dbt source freshness
```

**Generate and view documentation:**
```bash
dbt docs generate
dbt docs serve
```

## Notes / gotchas learned along the way

- `dbt run` never deletes objects for models removed from the project — renamed/deleted models leave orphaned tables/views in Snowflake that must be dropped manually.
- Newer dbt versions require source properties like `freshness` and `loaded_at_field` to be nested under a `config:` key rather than as top-level properties.
- Freshness checks require a genuine `TIMESTAMP` column (not `DATE`) for the `loaded_at_field` — a `DATE`-typed column raises a database error rather than a normal freshness result.
- This is a learning project, not a production setup — see the main bootcamp checklist for the CI/CD (GitHub Actions) work still ahead.

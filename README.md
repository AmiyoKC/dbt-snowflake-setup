# dbt + Snowflake Bootcamp

A hands-on dbt Core project connected to Snowflake, with full git-based CI/CD via GitHub Actions: automated testing on every pull request, automated deployment on every merge, and a daily scheduled production run.

## What this does

1. A small customer dataset is loaded into Snowflake as a **seed**.
2. A **staging model** (`stg_customers`) cleans and renames columns from that seed.
3. **Marts** build business logic on top: `daily_signups` (a date-spine aggregation) and `customer_activity` (an incremental table).
4. **Generic tests** (`unique`, `not_null`) validate data quality.
5. **GitHub Actions CI** runs the full `dbt build` against an isolated Snowflake schema on every pull request.
6. **GitHub Actions CD** deploys to a separate production schema on every merge to `main`, and on a daily schedule.

## Architecture

```
                    seeds/raw_customers.csv
                             |
                     dbt seed (ref, not source —
                     resolves per-environment)
                             v
              models/staging/stg_customers.sql
                             |
              -------------------------------
              |                              |
              v                              v
   models/marts/daily_signups     models/marts/customer_activity
   (uses dbt_utils.date_spine)    (incremental, unique_key)
              |
              v
      unique / not_null tests


  Pull Request                  Merge to main / Daily 9 PM IST
       |                                     |
       v                                     v
  GitHub Actions CI                  GitHub Actions CD
  dbt build -> DBT_CI schema         dbt build -> PROD schema
  role: DBT_CI_ROLE                  role: DBT_CI_ROLE
```

- **Snowflake** — data warehouse, with **three isolated schemas**:
  - `DBT_AMIYO` — personal local dev work
  - `DBT_CI` — CI's own isolated build target, used on every PR
  - `PROD` — production, deployed to on merge and daily
- **Key-pair authentication** — this Snowflake account requires MFA, which isn't compatible with password auth for unattended tools. Key-pair auth works identically for local dev and CI/CD — no passwords, no MFA prompts, anywhere in the automation.
- **`DBT_CI_ROLE`** — a least-privilege Snowflake role used by both CI and CD, scoped to only `DBT_CI` and `PROD` (full control) — deliberately has **no access at all** to the personal `DBT_AMIYO` schema, so a leaked secret or a build gone wrong can never touch local dev work.
- **`ref()` over `source()` for owned data** — `raw_customers` is a seed dbt builds itself, so `stg_customers` references it via `{{ ref('raw_customers') }}`, which resolves to whichever schema the *current* run targets. (An earlier version of this project used `{{ source(...) }}` with a hardcoded schema, which silently coupled every environment to one schema — a real bug caught and fixed during setup.)
- **dbt Core** — installed into an isolated conda environment (`dbt_bootcamp`) locally; installed fresh from `requirements.txt` on every CI/CD run, since GitHub's runners start from a blank machine every time.

## Project structure

```
.
├── .github/
│   └── workflows/
│       ├── ci.yml                    # runs dbt build on every PR, into DBT_CI
│       └── cd.yml                    # runs dbt build on merge to main + daily 9PM IST, into PROD
├── learn/                            # dbt project root
│   ├── dbt_project.yml
│   ├── packages.yml                    # dbt_utils dependency
│   ├── package-lock.yml
│   ├── requirements.txt                # pinned Python packages, used locally and in CI/CD
│   ├── models/
│   │   ├── staging/
│   │   │   ├── stg_customers.sql         # ref()'d from the raw_customers seed
│   │   │   └── _models.yml                 # descriptions + tests
│   │   └── marts/
│   │       ├── daily_signups.sql           # dbt_utils.date_spine example
│   │       ├── customer_activity.sql       # incremental model
│   │       └── _models.yml
│   ├── macros/
│   │   └── cents_to_dollars.sql          # example custom macro
│   └── seeds/
│       └── raw_customers.csv             # seed data
└── README.md
```

## Prerequisites

- A Snowflake account with `DBT_BOOTCAMP` database and `DBT_AMIYO`, `DBT_CI`, `PROD` schemas created
- A Snowflake user configured for key-pair auth (RSA key pair generated locally, public key registered via `ALTER USER <user> SET RSA_PUBLIC_KEY='...'`)
- A `DBT_CI_ROLE` in Snowflake, scoped per the grants below
- conda (or another Python env manager) installed locally
- A `~/.dbt/profiles.yml` entry named `learn`, pointing at the local private key path (never committed — lives outside the repo)
- GitHub repository secrets (see below)

## GitHub Secrets required

| Secret | Used for |
|---|---|
| `SNOWFLAKE_ACCOUNT` | Snowflake account identifier |
| `SNOWFLAKE_USER` | Snowflake username |
| `SNOWFLAKE_PRIVATE_KEY` | Full contents of the RSA private key (`rsa_key.p8`) |
| `SNOWFLAKE_DATABASE` | `DBT_BOOTCAMP` |
| `SNOWFLAKE_WAREHOUSE` | `COMPUTE_WH` |
| `SNOWFLAKE_CI_ROLE` | `DBT_CI_ROLE` — used by both CI and CD |
| `SNOWFLAKE_CI_SCHEMA` | `DBT_CI` — CI's isolated build target |
| `SNOWFLAKE_PROD_SCHEMA` | `PROD` — CD's deploy target |

## Snowflake role setup (least privilege)

```sql
CREATE ROLE IF NOT EXISTS DBT_CI_ROLE;

GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE DBT_CI_ROLE;
GRANT USAGE ON DATABASE DBT_BOOTCAMP TO ROLE DBT_CI_ROLE;

GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA DBT_BOOTCAMP.DBT_CI TO ROLE DBT_CI_ROLE;
GRANT ALL ON ALL TABLES IN SCHEMA DBT_BOOTCAMP.DBT_CI TO ROLE DBT_CI_ROLE;
GRANT ALL ON FUTURE TABLES IN SCHEMA DBT_BOOTCAMP.DBT_CI TO ROLE DBT_CI_ROLE;
GRANT ALL ON ALL VIEWS IN SCHEMA DBT_BOOTCAMP.DBT_CI TO ROLE DBT_CI_ROLE;
GRANT ALL ON FUTURE VIEWS IN SCHEMA DBT_BOOTCAMP.DBT_CI TO ROLE DBT_CI_ROLE;

GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA DBT_BOOTCAMP.PROD TO ROLE DBT_CI_ROLE;
GRANT ALL ON ALL TABLES IN SCHEMA DBT_BOOTCAMP.PROD TO ROLE DBT_CI_ROLE;
GRANT ALL ON FUTURE TABLES IN SCHEMA DBT_BOOTCAMP.PROD TO ROLE DBT_CI_ROLE;
GRANT ALL ON ALL VIEWS IN SCHEMA DBT_BOOTCAMP.PROD TO ROLE DBT_CI_ROLE;
GRANT ALL ON FUTURE VIEWS IN SCHEMA DBT_BOOTCAMP.PROD TO ROLE DBT_CI_ROLE;

GRANT ROLE DBT_CI_ROLE TO USER <your_username>;
```

Note: `DBT_CI_ROLE` deliberately has **no grants at all** on `DBT_AMIYO` — CI/CD never touch personal dev work.

## Running this yourself

**Set up the environment:**
```bash
conda create -n dbt_bootcamp python=3.10 -y
conda activate dbt_bootcamp
cd learn
pip install -r requirements.txt
dbt deps
```

**Verify the Snowflake connection:**
```bash
dbt debug
```

**Build everything (seeds, models, tests) from scratch:**
```bash
dbt build
```

**Check what any macro/model actually compiles to:**
```bash
dbt compile
cat target/compiled/learn/models/staging/stg_customers.sql
```

**Generate and view documentation:**
```bash
dbt docs generate
dbt docs serve
```

## CI/CD behavior

- **Any pull request into `main`** triggers `.github/workflows/ci.yml`: installs dbt fresh, authenticates via key-pair auth, and runs `dbt build` into the isolated `DBT_CI` schema. A red X on the PR blocks merging.
- **Any merge to `main`, or daily at 9:00 PM IST (15:30 UTC)**, triggers `.github/workflows/cd.yml`: runs `dbt build` into the `PROD` schema.
- Both workflows generate `~/.dbt/profiles.yml` fresh on the runner from GitHub Secrets — no credentials are ever committed to the repo.

## Notes / gotchas learned along the way

- `dbt run`/`dbt build` never delete objects for models removed from the project — renamed/deleted models leave orphaned tables/views that must be dropped manually.
- Newer dbt versions require source properties (`freshness`, `loaded_at_field`) nested under a `config:` key rather than as top-level properties.
- Freshness checks require a genuine `TIMESTAMP` column, not `DATE`, for `loaded_at_field`.
- `dbt build` includes seeds, models, and tests in DAG order — but only when dependencies are declared via `ref()`. A `source()` declaration with a hardcoded schema will not be environment-aware, and can silently point every environment at the same physical schema.
- In Snowflake, the role that **creates** an object becomes its owner — a more privileged role (like `ACCOUNTADMIN`) doesn't automatically gain rights over objects a different role created; ownership must be explicitly granted or the creating role must be used.
- A GitHub Actions branch pushed for the first time needs `git push -u origin <branch>` to set upstream tracking; plain `git push` works on every push after that.
- `.github/workflows/` must live at the repository root — it's not detected if nested inside a subproject folder.
- This is a learning project, not a production setup — see "Known gaps" below.

## Known gaps / good next steps

- **Slim CI** — using `--select state:modified+ --defer --state` so CI only rebuilds changed models, instead of the whole project every time.
- **Docker image** for the dbt project, for more portable/reproducible CI runs.
- **A proper orchestrator** (Airflow, Dagster, dbt Cloud's scheduler) instead of GitHub Actions' `schedule:` cron trigger, once there's real cross-system dependency logic (e.g., "wait for an upstream loader to finish").
- **dbt Semantic Layer / MCP server**, if this data is ever meant to be queried by an AI agent rather than a person.

# Snowflake Company Data dbt Package

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![dbt-core](https://img.shields.io/badge/dbt--core-%3E%3D1.10.0%20%3C3.0.0-orange.svg)](https://github.com/dbt-labs/dbt-core)
[![Warehouse: Snowflake](https://img.shields.io/badge/warehouse-Snowflake-29B5E8.svg)](https://www.snowflake.com/)
[![Status: pre-1.0](https://img.shields.io/badge/status-pre--1.0-yellow.svg)](CHANGELOG.md)

Turn Snowflake's free public company data into a modeling layer you can actually build on: clean staging models, resolved company entities, and a matching layer that joins your own accounts or leads to the public company spine.

> **Status: pre-1.0 and under active development.** The model interface may change between minor versions. Pin to a minor range (see [Install](#install)) and read the [CHANGELOG](CHANGELOG.md) before upgrading.

---

## Why This Exists

Snowflake gives away a reference spine of **2.9 million** public and private companies, plus SEC filings, security identifiers, and geography, at no cost through the Marketplace. The data is genuinely useful and the raw shape is genuinely awkward:

- Company attributes are stored **entity-attribute-value**, so industry classification is a row filter, not a column.
- Some identifiers are **ARRAY-typed**, so a company can carry several LEIs and a naive join fans out.
- The company-to-security join is **`ARRAY_CONTAINS`, not equality**, which dbt's built-in `relationships` test cannot express at all.

This package absorbs that complexity once so you do not have to solve it in every project that touches the data.

## What It Does

| Model | Grain | Rows |
|---|---|---|
| `snoco__companies` | one row per company | 2,918,929 |
| `snoco__company_identifiers` | company + identifier type + value | 3,913,860 |
| `snoco__company_domains` | company + domain | 319,269 |
| `snoco__company_securities` | company + security type + id | 985,971 |
| `snoco__company_hierarchy` | one row per root-to-company path | 713 |
| `snoco__company_match_candidates` | your record + company + method | opt-in |
| `snoco__company_match` | one row per matched record of yours | opt-in |

Nine staging models sit underneath, one per source object, renamed and typed and
nothing else. Three public macros are usable on their own:
`normalize_company_name`, `company_name_similarity`, and the blocking key.

Row counts are from the free share as of 2026-08-08 and will drift.

Two things the table above will not tell you, so they are said here. The
**hierarchy is nearly empty**: 424 edges against 2.9M companies, roughly 0.015%
coverage. And there is **no employee count and no revenue** anywhere in the free
share, so this is an enrichment and resolution layer, not a prospecting
database.

See [DECISIONLOG.md](https://github.com/zelloptt/dbt-snowflake-company-data/blob/main/DECISIONLOG.md) for the reasoning behind each modeling choice.

## Warehouse Support

**Snowflake only.** The data source is a Snowflake Marketplace share, so there is no cross-warehouse story and the package does not pretend otherwise.

## Prerequisites

Two setup steps account for essentially every "it does not work" report. Do both before installing.

**1. Get the data.** Acquire the [Snowflake Public Data (Free)](https://app.snowflake.com/marketplace/listing/GZTSZ290BV255) listing in your account. Your organization must accept Snowflake's provider and consumer terms at the ORGADMIN level first; you cannot obtain the listing until that happens.

```sql
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_PUBLIC_DATA_FREE FROM LISTING 'GZTSZ290BV255';
```

The database name is yours to choose at install time. Whatever you pick, tell the package about it (see [Configure](#configure)).

**2. Grant access to your dbt role.** By default *only the role that created the database can read it*. This is the single most common failure:

```sql
GRANT IMPORTED PRIVILEGES ON DATABASE <your_database> TO ROLE <your_dbt_role>;
```

## Install

Add to `packages.yml` in your dbt project:

```yaml
packages:
  - package: zelloptt/snowflake_company_data
    version: [">=0.1.0", "<0.2.0"]
```

Then `dbt deps`.

While pre-1.0, pin to a minor range. Breaking changes ship as minor bumps until 1.0.0, which is standard semver practice for 0.x and is why the upper bound matters. If your project uses `dependencies.yml` instead, add the same block there.

## Configure

**You must set both location vars.** There is no default that works
unconfigured, because the share's database name is chosen by whoever runs
`CREATE DATABASE ... FROM LISTING` and is different in every account.

```yaml
vars:
  snowflake_company_data:
    snoco_database: MY_PUBLIC_DATA_DB
    snoco_schema: PUBLIC_DATA_FREE
```

The shipped defaults describe the maintainers' own deployment, which reads a
daily replica of the share rather than the share itself. If you leave them
alone you will get a "does not exist or not authorized" error naming a database
you have never heard of. That is this setting being unset, not a bug.

Both layouts work and the package cannot tell them apart, which is the point:

| You read | `snoco_database` | `snoco_schema` |
|---|---|---|
| The Marketplace share directly | whatever you named it at `CREATE DATABASE` | `PUBLIC_DATA_FREE` |
| Your own replica of it | your database | your schema |

A replica is worth considering. The share exposes secure views whose
`ROW_COUNT` and `BYTES` are `NULL`, so nothing downstream can reason about
size, and no object in it carries a load timestamp of any kind. Cloning the ten
objects this package reads into your own schema costs little and gives you both
back.

### Source freshness

Not configured by this package, deliberately: nothing in the share carries a
load timestamp, and `LAST_ALTERED` reflects DDL and background metadata
operations rather than data loads, so any freshness shipped here would be a
confident wrong answer.

If you read a replica that has a real anchor, turn it on from your own
`dbt_project.yml`:

```yaml
sources:
  snowflake_company_data:
    snoco:
      +loaded_at_field: cloned_at
      +freshness:
        warn_after: {count: 36, period: hour}
        error_after: {count: 72, period: hour}
```

### Output schemas

By default the package builds into two schemas alongside your own models:

- `<target_schema>_snowflake_company_data` for the entity and matching models
- `<target_schema>_stg_snowflake_company_data` for staging

Override either:

```yaml
models:
  snowflake_company_data:
    +schema: my_schema_name
    staging:
      +schema: my_staging_schema_name
```

### Enable and disable

Every domain and source table has an `_enabled` flag defaulting to `true`, so you can build only what you need:

```yaml
vars:
  snowflake_company_data:
    snoco_company_enabled: true
    snoco_sec_enabled: false
    snoco_securities_enabled: false
    snoco_matching_enabled: false   # off by default; requires configuration below
```

### Matching layer

Disabled by default because it needs to know where your data lives. Point it at a relation and map your columns:

```yaml
vars:
  snowflake_company_data:
    snoco_matching_enabled: true
    snoco__match_source: dim_accounts      # a model name, resolved with ref()
    snoco__match_id_column: account_id
    snoco__match_name_column: account_name
    snoco__match_domain_column: website_domain
    snoco__match_min_score: 0.90
    snoco__match_max_candidates: 5
```

`snoco__match_source` takes either a model name, resolved with `ref()`, or a
fully qualified relation such as `analytics.crm.dim_accounts` if you would
rather point at a raw table than wrap it in a model. Anything containing a dot
is treated as the latter.

Two models come out. `snoco__company_match_candidates` keeps every plausible
company with the evidence that produced it, for review.
`snoco__company_match` picks one winner per input row.

Matching runs two methods and keeps them separate rather than blending them
into one number:

- **domain** is deterministic and scored `1.0`. Your domain equals a domain the
  share attributes to that company. `snoco__match_min_score` does not apply,
  because a domain match is an identity assertion rather than a similarity.
  Domains that resolve to several companies are still returned, flagged
  `is_shared_domain`, so the ambiguity is visible instead of arbitrarily
  resolved.
- **name** is fuzzy and blocked. Only companies sharing a cheap blocking key
  with your normalised name are scored at all, which is what makes the thing
  finish against a 2.9M-row spine. The cost is recall: two names that differ in
  their first four characters can never match, so `ibm` will not find
  `international business machines`. Run domain matching alongside it.

Rows where the runner-up scored within `snoco__match_ambiguity_margin` of the
winner are flagged `is_ambiguous`. The winner is still a real answer, just not a
confident one.

Input rows with no candidate above the threshold are **absent** from
`snoco__company_match` rather than present with a null `company_id`, so a left
join from your own table gives you the unmatched set without a filter.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](https://github.com/zelloptt/dbt-snowflake-company-data/blob/main/CONTRIBUTING.md).

## Data, Attribution, and Licensing

**This package contains SQL only.** It does not include, redistribute, or grant any rights to the underlying data. You acquire the dataset yourself, directly from Snowflake, under Snowflake's terms.

The underlying data is public domain and originates with the US Securities and Exchange Commission, GLEIF, OpenFIGI, and Refinitiv/PermID. Per Snowflake's own disclaimer for this listing: *Snowflake is not endorsed by or affiliated with any of these providers.*

The SQL, macros, seeds, and documentation in this repository are licensed under [Apache 2.0](LICENSE). That license covers this package's code and nothing else. The authors make no representation about your right to use the underlying data and provide no warranty as to fitness for any purpose.

Snowflake is a trademark of Snowflake Inc. This package is an independent open-source project and is not affiliated with, endorsed by, or sponsored by Snowflake Inc.

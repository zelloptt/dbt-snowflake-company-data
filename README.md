# Snowflake Company Data dbt Package

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![dbt-core](https://img.shields.io/badge/dbt--core-%3E%3D1.10.0%20%3C3.0.0-orange.svg)](https://github.com/dbt-labs/dbt-core)
[![Warehouse: Snowflake](https://img.shields.io/badge/warehouse-Snowflake-29B5E8.svg)](https://www.snowflake.com/)
[![Status: pre-1.0](https://img.shields.io/badge/status-pre--1.0-yellow.svg)](CHANGELOG.md)

Turn Snowflake's free public company data into a modeling layer you can actually build on: clean staging models, resolved company entities, and a matching layer that joins your own accounts or leads to the public company spine.

> **Status: pre-1.0 and under active development.** The model interface may change between minor versions. Pin to a minor range (see [Install](#install)) and read the [CHANGELOG](CHANGELOG.md) before upgrading.

---

## Why This Exists

Snowflake gives away a reference spine of roughly 100,000 public and private companies, plus SEC filings, security identifiers, and geography, at no cost through the Marketplace. The data is genuinely useful and the raw shape is genuinely awkward:

- Company attributes are stored **entity-attribute-value**, so industry classification is a row filter, not a column.
- Some identifiers are **ARRAY-typed**, so a company can carry several LEIs and a naive join fans out.
- The company-to-security join is **`ARRAY_CONTAINS`, not equality**, which dbt's built-in `relationships` test cannot express at all.

This package absorbs that complexity once so you do not have to solve it in every project that touches the data.

## What It Does

| Layer | What you get |
|---|---|
| **Staging** | One model per source table. Renamed, typed, documented. Nothing else. |
| **Entities** | A one-row-per-company spine, a tidy identifier table, resolved characteristics, industry rollups, and securities. |
| **Matching** | Deterministic identifier joins plus blocked fuzzy name matching, so you can attach your own CRM records to the public spine. |
| **Macros** | Company name normalization, match scoring, and blocking, usable on their own. |

Full model list arrives with the first release. See [DECISIONLOG.md](https://github.com/zelloptt/dbt-snowflake-company-data/blob/main/DECISIONLOG.md) for the reasoning behind each modeling choice.

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

At minimum, point the package at your copy of the share:

```yaml
vars:
  snowflake_company_data:
    snoco_database: MY_PUBLIC_DATA_DB    # defaults to SNOWFLAKE_PUBLIC_DATA_FREE
    snoco_schema: PUBLIC_DATA_FREE       # provider-controlled, rarely changes
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
    snoco__match_source: "ref('dim_accounts')"
    snoco__match_id_column: account_id
    snoco__match_name_column: account_name
    snoco__match_domain_column: website_domain
    snoco__match_min_score: 0.90
    snoco__match_max_candidates: 5
```

Two models come out: `snoco__company_match_candidates` for review, and `snoco__company_match` with one deterministic best match per input row.

Full variable reference lands with the first release.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](https://github.com/zelloptt/dbt-snowflake-company-data/blob/main/CONTRIBUTING.md).

## Data, Attribution, and Licensing

**This package contains SQL only.** It does not include, redistribute, or grant any rights to the underlying data. You acquire the dataset yourself, directly from Snowflake, under Snowflake's terms.

The underlying data is public domain and originates with the US Securities and Exchange Commission, GLEIF, OpenFIGI, and Refinitiv/PermID. Per Snowflake's own disclaimer for this listing: *Snowflake is not endorsed by or affiliated with any of these providers.*

The SQL, macros, seeds, and documentation in this repository are licensed under [Apache 2.0](LICENSE). That license covers this package's code and nothing else. The authors make no representation about your right to use the underlying data and provide no warranty as to fitness for any purpose.

Snowflake is a trademark of Snowflake Inc. This package is an independent open-source project and is not affiliated with, endorsed by, or sponsored by Snowflake Inc.

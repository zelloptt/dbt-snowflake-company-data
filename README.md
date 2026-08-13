# Snowflake Company Data dbt Package

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![dbt-core](https://img.shields.io/badge/dbt--core-%3E%3D1.10.8%20%3C3.0.0-orange.svg)](https://github.com/dbt-labs/dbt-core)
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
nothing else. `snoco__edgar_state_country_codes` ships the SEC's EDGAR
state-or-country list, so `X1` has a name. Three public macros
are usable on their own: `normalize_company_name`, `normalize_domain` and
`company_name_similarity`.
(The blocking key is `_blocking_key`, which is private: the leading underscore
means it is an implementation detail of the matching models and its signature
may change in a patch release.)

Row counts are from the free share as of 2026-08-08 and will drift.

Three things the table above will not tell you, so they are said here. The
**hierarchy is nearly empty**: 424 edges against 2.9M companies, roughly 0.015%
coverage. There is **no employee count and no revenue** anywhere in the free
share, so this is an enrichment and resolution layer, not a prospecting
database. And **`country` on the source is an EDGAR state-or-country code, not
ISO**: `X1` is the United States. Filter `snoco__companies` on
`country_iso_alpha2` and `state_iso_3166_2`. `edgar_country_name` is the
readable form. Empty strings and the `XX` placeholder are NULL.

See [DECISIONLOG.md](https://github.com/zelloptt/dbt-snowflake-company-data/blob/main/DECISIONLOG.md) for the reasoning behind each modeling choice.

## Warehouse Support

**Snowflake only.** The data source is a Snowflake Marketplace share, so there is no cross-warehouse story and the package does not pretend otherwise.

## Prerequisites

Two setup steps account for essentially every "it does not work" report. Do both before installing.

**1. Get the data.** Acquire the [Snowflake Public Data (Free)](https://app.snowflake.com/marketplace/listing/GZTSZ290BV255) listing in your account. Your organization must accept Snowflake's provider and consumer terms at the ORGADMIN level first; you cannot obtain the listing until that happens.

```sql
CREATE DATABASE IF NOT EXISTS MARKETPLACE_CYBERSYN FROM LISTING 'GZTSZ290BV255';
```

`MARKETPLACE_CYBERSYN` is the name Snowflake proposes and the name this package defaults to. You may pick another; if you do, tell the package (see [Configure](#configure)).

**2. Grant access to your dbt role.** By default *only the role that created the database can read it*. This is the single most common failure:

```sql
GRANT IMPORTED PRIVILEGES ON DATABASE <your_database> TO ROLE <your_dbt_role>;
```

## Install

**Install from git.** The package is not yet listed on the dbt Package Hub, so
hub syntax does not resolve for it. Add to `packages.yml` in your dbt project:

```yaml
packages:
  - git: "https://github.com/zelloptt/dbt-snowflake-company-data.git"
    revision: 0.2.0
```

Then `dbt deps`. Pin `revision` to a release tag, never to a branch. A branch
moves under you and dbt warns about the unpinned dependency.

One cost worth knowing: a git install clones the repository, and a clone ignores
the `export-ignore` rules that keep development files out of a Package Hub
install. `integration_tests/`, `.github/` and our contributor documentation land
in your `dbt_packages/` alongside the package. None of it is parsed, since dbt
reads only the paths this package's `dbt_project.yml` declares. It is heavier
than it needs to be, and that is the whole of the problem.

**Once the package is listed on the hub**, prefer this form. It is shorter, it
resolves version ranges, and it delivers only the 38 files that are actually the
package:

```yaml
packages:
  - package: zelloptt/snowflake_company_data
    version: [">=0.2.0", "<0.3.0"]
```

While pre-1.0, pin to a minor range. Breaking changes ship as minor bumps until 1.0.0, which is standard semver practice for 0.x and is why the upper bound matters. If your project uses `dependencies.yml` instead, add the same block there.

## Configure

The defaults match the names Snowflake proposes when you acquire the listing:

```yaml
vars:
  snowflake_company_data:
    snoco_database: MARKETPLACE_CYBERSYN   # default
    snoco_schema: PUBLIC_DATA_FREE         # default
```

If you accepted the suggested database name, there is nothing to configure. If
you named it something else, which the `CREATE DATABASE ... FROM LISTING`
statement lets you do, set `snoco_database` to match.

> **`CYBERSYN` is also a schema in this listing, and it is the wrong one.** It
> is the older Financial Data Package layout and carries only 6 of the 9 objects
> this package reads: `COMPANY_CHARACTERISTICS`, `COMPANY_DOMAIN_RELATIONSHIPS`
> and `SEC_CIK_INDEX` are absent, which is every company attribute, every
> domain, and all SIC and address data. Use `PUBLIC_DATA_FREE`.

| You read | `snoco_database` | `snoco_schema` |
|---|---|---|
| The share, default name | `MARKETPLACE_CYBERSYN` | `PUBLIC_DATA_FREE` |
| The share, your own name | whatever you named it | `PUBLIC_DATA_FREE` |
| Your own replica of it | your database | your schema |

That third row is the one most projects end up on. See
[Reading a replica instead of the share](#reading-a-replica-instead-of-the-share).

### Reading a replica instead of the share

Pointing the package at the share works and is the fastest way to get started.
Pointing it at your own copy is where most projects end up, and it is the reason
`snoco_schema` is a variable rather than a constant.

**What the share costs you.** All nine objects are secure views, and that takes
three things away:

- **No size signal.** `INFORMATION_SCHEMA.TABLES.ROW_COUNT` and `BYTES` are
  `NULL` for every object in the share, so nothing downstream, including your
  own cost and observability tooling, can reason about how big any of this is.
- **No freshness anchor.** No object carries a load timestamp of any kind, and
  `LAST_ALTERED` reflects DDL and background metadata operations rather than
  data loads. There is nothing honest to point `loaded_at_field` at.
- **No control over when the data moves.** The provider republishes on their
  schedule. A build that starts before a republish and ends after it has read
  two different versions of the spine.

A copy on your own schedule gives all three back.

**Making the copy.** Copy the nine objects this package reads into one schema you
own, adding your own timestamp on the way through:

```sql
CREATE SCHEMA IF NOT EXISTS <your_db>.<your_schema>;

CREATE OR REPLACE TABLE <your_db>.<your_schema>.COMPANY_INDEX AS
SELECT *, CURRENT_TIMESTAMP() AS cloned_at
FROM MARKETPLACE_CYBERSYN.PUBLIC_DATA_FREE.COMPANY_INDEX;

-- and the same for the other eight:
--   COMPANY_CHARACTERISTICS
--   COMPANY_DOMAIN_RELATIONSHIPS
--   COMPANY_RELATIONSHIPS
--   COMPANY_SECURITY_RELATIONSHIPS
--   SEC_CIK_INDEX
--   OPENFIGI_SECURITY_INDEX
--   PERMID_SECURITY_INDEX
--   GEOGRAPHY_INDEX
```

`CREATE TABLE ... CLONE` is not the mechanism. Snowflake does not support
cloning out of a database created from a listing, and these are views rather
than tables in any case, so it is `CREATE TABLE ... AS SELECT`.

The extra `cloned_at` column is safe. Staging models select named columns, so a
column the package does not know about is ignored rather than a schema conflict.

If you run the copy on a schedule, guard it on a row count before you replace
anything. `CREATE OR REPLACE` on a degenerate pull swaps a good table for an
empty one and nothing downstream will tell you. Per-object counts as of the last
measurement are in each table's description in
`models/staging/_snoco__sources.yml`, which ships with the package; a floor
around 85% of the last known good count catches a truncated pull without firing
on ordinary drift.

**Pointing the package at it:**

```yaml
vars:
  snowflake_company_data:
    snoco_database: <your_db>
    snoco_schema: <your_schema>
```

**Keep the replica in one schema.** The share puts everything in one
(`PUBLIC_DATA_FREE`) and the package addresses all nine objects with exactly
those two vars, so a single-schema replica keeps switching between the share and
your copy a two-line change. If you genuinely cannot, each object also has its
own relation var and can be repointed on its own:

```yaml
vars:
  snowflake_company_data:
    snoco_sec_cik_index: "{{ source('my_other_source', 'sec_cik_index') }}"
```

Those vars take any relation: a `source()` call, a `ref()`, or a bare fully
qualified name. A `source()` or `ref()` still registers in the DAG, because the
expression is rendered in the consuming model's context rather than the
package's. A bare name is not a node and so has no lineage, which is the
trade-off for pointing at something dbt does not manage.

### Source freshness

Not configured by this package, deliberately: nothing in the share carries a
load timestamp, and `LAST_ALTERED` reflects DDL and background metadata
operations rather than data loads, so any freshness shipped here would be a
confident wrong answer.

A replica has a real anchor. Turn it on from your own `dbt_project.yml`, which
is also the only place you can, since dbt parses schema YAML before it renders
Jinja and a package var therefore cannot reach a `freshness` block:

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

> **If your project overrides `generate_schema_name`, read this.** Every model in
> this package resolves to a non-null custom schema name, because
> `dbt_project.yml` sets `+schema` at the package root and again on `staging/`.
> That is deliberate and it is load-bearing rather than cosmetic.
>
> A common override shape branches on `custom_schema_name is none` and falls back
> to deriving a schema from the node's path or file name. That is correct for
> models in your own project and nonsense for models in someone else's package:
> the staging model's own file name comes back as the schema name. Because this
> package always supplies a custom schema name, your override takes its normal
> branch and the fallback is never reached.
>
> So: override the value, do not remove the key. A config block that sets
> `+materialized` on the package without also setting `+schema` is fine, since
> the package's own `+schema` still applies, but anything that nulls it out is
> not.

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

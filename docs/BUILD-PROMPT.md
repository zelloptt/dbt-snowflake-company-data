> **HISTORICAL ARTIFACT. Do not follow this document.**
>
> This is the prompt that specified the package before it was built. The package
> now exists and diverges from it in ways that were decided by measurement rather
> than by plan: the layout is flat marts at the root of `models/` rather than
> themed subdirectories, sources are addressed by relation vars rather than
> identifier vars, the spine is 2.9M rows rather than the ~100K assumed here, and
> the dbt floor is 1.10.8 rather than 1.10.0.
>
> Kept for provenance, because the reasoning behind several decisions only makes
> sense against what was originally asked for. For what the package actually is,
> read `README.md`, `DECISIONLOG.md` and `docs/DISCOVERY.md`.

# Build Prompt: `dbt-snowflake-company-data`

Run this from inside the empty (or `git init`'d) package repository. It assumes you have a Snowflake connection profile that can query the free public data share.

Before pasting: if you want a different package name, change only the **Naming** block in section 0. Everything else derives from it.

---

## COPY FROM HERE

You are building an open source dbt package that I intend to publish on the dbt Package Hub. Work in this repository. Do not create a subdirectory for the package; the repo root is the package root.

Read this entire brief before doing anything. Then execute the phases in order. Stop and ask me at the checkpoints marked **CHECKPOINT**.

---

# 0. What we are building

A dbt package that turns Snowflake's free public company data into a usable, tested, documented modeling layer, plus a matching layer that lets someone join their own accounts or leads to it.

The package has four jobs:

1. **Staging.** Normalize the raw shared tables into clean, typed, renamed staging models.
2. **Entity models.** Resolve the awkward parts of the raw shape (EAV characteristics, ARRAY-typed identifiers, bidirectional relationship edges) into models people can actually join to.
3. **Enrichment / matching.** Match a user-supplied relation of company names and domains against the public company spine, with deterministic identifier matches first and fuzzy name matching as a fallback.
4. **Macros.** The reusable pieces factored out so people can use them independently.

## Naming

- Repo name: `dbt-snowflake-company-data`
- Package name in `dbt_project.yml`: `snowflake_company_data`
- Model infix: `snoco`
  - Staging: `stg_snoco__company_index`
  - Intermediate: `int_snoco__company_lei_flattened`
  - Marts: `snoco__companies`
- Variable prefix: `snoco_` for location and enablement, `snoco__` for user-facing config

The infix exists because hubcap's best practices require packages to disambiguate resource names against nodes likely to exist already in a consumer project ("packages SHOULD NOT provide a model simply called `users`"). Do not drop it. Note: `require_unique_project_resource_names` (introduced dbt 1.11, still off by default) enforces uniqueness *within* a package, not against the consumer's project, so it is not the reason.

## Warehouse support

**Snowflake only.** The data source is a Snowflake Marketplace share, so there is no cross-warehouse story. Say so plainly in the README. Do not add `adapter.dispatch` scaffolding for other warehouses; it is dead weight here. Do still use `dbt.type_string()`, `dbt.type_timestamp()` and friends instead of literal types, because it costs nothing and keeps the door open.

---

# 1. Ground rules

These are non-negotiable. Violating any of them means rework later.

1. **The shared database is read only.** Snowflake forbids creating any object inside a database created from a listing. Every model materializes into the user's own database. Never set `store_failures` to a target inside the share. Never write a snapshot there.

2. **Never hard-code a database or schema name.** hubcap's package best practices make this a MUST. Everything goes through vars.

3. **Do not trust any table or column name I have given you, or that you recall.** The public documentation for this dataset is thin and partially wrong. Phase 0 exists to establish ground truth by introspection. If a column you expected does not exist, change the model, do not invent the column.

4. **`require-dbt-version: [">=1.10.0", "<3.0.0"]`.** The `<3.0.0` ceiling is deliberate: the dbt Fusion engine reports itself as 2.x. A `<2.0.0` ceiling costs you the Fusion-compatible badge on the hub and makes Fusion warn today, and dbt has said it will error in a future release. You will see `<2.0.0` recommended in hubcap's own best-practices doc; that example is stale, though it will not block listing.

5. **Generic test arguments nest under `arguments:`.** The `require_generic_test_arguments_property` behavior flag matured to true in dbt 1.10.8.

6. **Do not use `dbt_utils.unique_combination_of_columns`.** dbt-core 1.10.6 broke multi-argument test syntax and Fivetran deleted every instance of this test across their packages rather than migrate it. For composite keys, build a surrogate key column in the model and test `unique` on that.

7. **Prefer loud failures to silent nulls.** Do not implement Fivetran's `fill_staging_columns` / `tmp/` pattern. That pattern exists to survive per-tenant schema variance from SaaS connectors. Every consumer of this package reads the *same* share, so a schema change breaks everyone identically and we want to find out immediately.

8. **No data in the repo.** The package ships SQL, not data. Any seed derived from the share would be redistribution and our license does not cover it. Integration test fixtures must be synthetic. A SIC code reference seed is fine, because SIC is a US government classification standard, not vendor data.

9. **Views by default in staging, tables only where real work happens.** dbt's official package guidance is to default to views. Note the spine is **2.9M rows, not the ~100K this document originally assumed** (measured; see `docs/DISCOVERY.md`). The conclusion is unchanged but the reason is different: staging here is a rename and a cast over an already-materialised source, so a table would be a second copy earning nothing. Materialise where work happens, which is the marts.

---

# 2. Phase 0: Establish ground truth (do this first, write no models yet)

Connect to Snowflake and introspect. My local database name for the share is `MARKETPLACE_CYBERSYN` and the schema is `PUBLIC_DATA_FREE`, but confirm both.

**Run queries 1 and 2 first, then generate 3 through 8 from what query 2 actually returns.** The column names below are my best guess from public documentation and several of them are uncorroborated. Do not paste queries 3 through 8 blind; rewrite them against the real column contract. Ground rule 3 applies to this section too.

```sql
-- 1. Confirm the schema and inventory every table
--    ROW_COUNT and BYTES are often null for share-derived objects (Marketplace
--    listings frequently expose secure views). Treat them as a hint, not a fact;
--    query 3 is the trustworthy count.
select table_schema, table_name, row_count, bytes, last_altered, comment
from MARKETPLACE_CYBERSYN.information_schema.tables
where table_schema = 'PUBLIC_DATA_FREE'
order by table_name;

-- 2. Full column contract for the company family and its neighbours
select table_name, ordinal_position, column_name, data_type, is_nullable, comment
from MARKETPLACE_CYBERSYN.information_schema.columns
where table_schema = 'PUBLIC_DATA_FREE'
  and (table_name like 'COMPANY%'
       or table_name like 'SEC_%'
       or table_name like 'GEOGRAPHY%'
       or table_name like '%SECURITY_INDEX')
order by table_name, ordinal_position;

-- 3. Row counts, actual not estimated, for the tables we will model
select 'COMPANY_INDEX' as t, count(*) as n from MARKETPLACE_CYBERSYN.PUBLIC_DATA_FREE.company_index
union all select 'COMPANY_CHARACTERISTICS', count(*) from MARKETPLACE_CYBERSYN.PUBLIC_DATA_FREE.company_characteristics
union all select 'COMPANY_RELATIONSHIPS', count(*) from MARKETPLACE_CYBERSYN.PUBLIC_DATA_FREE.company_relationships
union all select 'COMPANY_SECURITY_RELATIONSHIPS', count(*) from MARKETPLACE_CYBERSYN.PUBLIC_DATA_FREE.company_security_relationships;

-- 4. The EAV vocabulary. This drives the whole characteristics design.
select relationship_type, count(*) as n, count(distinct company_id) as n_companies
from MARKETPLACE_CYBERSYN.PUBLIC_DATA_FREE.company_characteristics
group by 1 order by 2 desc;

-- 5. Uniqueness and null profile of the spine
select count(*) as n_rows, count(distinct company_id) as n_ids,
       count(cik) as n_cik, count(ein) as n_ein, count(permid_company_id) as n_permid
from MARKETPLACE_CYBERSYN.PUBLIC_DATA_FREE.company_index;

-- 6. Confirm which columns are ARRAY. Adjust names to what query 2 returned.
select company_id, lei, typeof(to_variant(lei)) as lei_type
from MARKETPLACE_CYBERSYN.PUBLIC_DATA_FREE.company_index
where lei is not null limit 5;

-- 7. Relationship shape: is the edge list bidirectional?
select relationship_type, count(*) from MARKETPLACE_CYBERSYN.PUBLIC_DATA_FREE.company_relationships group by 1;

-- 8. Freshness feasibility: is LAST_ALTERED even populated?
--    Do NOT probe with "order by last_altered desc limit 10" -- Snowflake sorts
--    NULLS FIRST on DESC, so an empty column looks inconclusive rather than empty.
select count(*) as n_tables, count(last_altered) as n_with_last_altered
from MARKETPLACE_CYBERSYN.information_schema.tables
where table_schema = 'PUBLIC_DATA_FREE';
```

Note on freshness regardless of the answer: Snowflake's own usage notes say `LAST_ALTERED` reflects DDL and background metadata operations, not data loads. It is not a freshness signal. Combined with dbt-core issue #12945 (open, `loaded_at_field` under `config:` being ignored), the conclusion is to ship freshness off by default and document the opt-in.

Also, do not `USE SCHEMA INFORMATION_SCHEMA` on a share-derived database. Snowflake documents that selecting it as the session schema can fail with "does not exist or is not authorized." Fully qualified references, as written above, are fine.

Write everything you learn to `DISCOVERY.md` at the repo root, structured as:

- Confirmed database and schema
- Table inventory with row counts and byte sizes
- Per-table column contract (name, type, nullability, observed cardinality)
- Which columns are ARRAY or VARIANT
- The full `relationship_type` vocabulary from `COMPANY_CHARACTERISTICS`, with counts, and your recommendation for which ones to pivot into a wide table by default
- Whether `COMPANY_HIERARCHY` and `COMPANY_FINANCIALS` exist (I have found no evidence they do; hierarchy appears to live in `COMPANY_RELATIONSHIPS.relationship_type`)
- **Whether `COMPANY_RELATIONSHIPS` exists in the free schema at all.** My only source for its shape is the Cybersyn *premium* data dictionary, and no public example queries the free schema for it. Three planned marts depend on it (`snoco__company_hierarchy`, `snoco__company_ultimate_parent`, `int_snoco__company_edges`). If it is absent or paid-only, say so at CHECKPOINT 1 and we cut those models from v0.1.0 rather than shimming around it.
- The exact name of the transcript table. It appears as both `COMPANY_EVENT_TRANSCRIPT_ATTRIBUTES` and `COMPANY_EVENT_TRANSCRIPT_ATTRIBUTES_V2` in different Snowflake-Labs repos.
- Whether `COMPANY_INDEX` carries ticker and exchange columns, or whether those live only on the security index tables
- Which `SEC_*` tables are present in the free schema
- Whether `LAST_ALTERED` is usable for source freshness
- Anything surprising

`DISCOVERY.md` is a working document, not a deliverable. Keep it in the repo; it is the evidence trail for every modeling decision and it is exactly the kind of git history hubcap now looks for.

**CHECKPOINT 1.** Show me `DISCOVERY.md` and your proposed model list before writing any SQL.

---

# 3. Phase 1: Repo scaffold

**Most of this already exists.** The repo was bootstrapped with `dbt_project.yml`, `packages.yml`, `LICENSE`, `README.md`, `CHANGELOG.md`, `DECISIONLOG.md`, `CONTRIBUTING.md`, `RELEASE.md`, `CLAUDE.md`, `.gitignore`, `.github/` templates, `CODEOWNERS`, and `integration_tests/profiles.yml.example`. Read `CLAUDE.md` first; it is the authority on conventions and it already encodes the ground rules above.

Your job in this phase is to fill the gaps, not to recreate what is there. Missing: `integration_tests/dbt_project.yml`, `.github/workflows/`, and every model, macro, seed, and test. The empty scaffold directories and their `.gitkeep` files were removed; git recreates a directory as soon as a real file lands in it. Anything you add under `models/`, `macros/`, `seeds/`, `tests/`, `snapshots/`, or `analyses/` ships to consumers, so check `.gitattributes` before adding a path anywhere else.

For reference, the target structure:

```
dbt-snowflake-company-data/
├── dbt_project.yml
├── packages.yml
├── LICENSE                          # Apache 2.0
├── README.md
├── CHANGELOG.md
├── DECISIONLOG.md
├── CONTRIBUTING.md
├── RELEASE.md
├── CLAUDE.md                        # conventions, so future sessions stay consistent
├── DISCOVERY.md
├── macros/
│   ├── _macros.yml
│   ├── enabled_vars.sql
│   ├── normalize_company_name.sql
│   ├── get_characteristic_types.sql
│   └── match/
│       ├── company_match_score.sql
│       └── blocking_key.sql
├── models/
│   ├── docs.md
│   ├── staging/
│   │   ├── src_snowflake_company_data.yml
│   │   ├── stg_snoco__*.sql
│   │   ├── stg_snoco__*.yml
│   │   └── docs.md
│   ├── intermediate/
│   │   └── int_snoco__*.sql
│   ├── companies/
│   │   ├── snoco__*.sql
│   │   └── companies.yml
│   └── matching/
│       ├── snoco__company_match_candidates.sql
│       ├── snoco__company_match.sql
│       └── matching.yml
├── seeds/
│   └── snoco_sic_division_reference.csv
├── tests/
│   └── generic/
├── integration_tests/
│   ├── dbt_project.yml
│   ├── packages.yml                 # - local: ../
│   ├── profiles.yml.example
│   ├── ci/test_scenarios.yml
│   ├── seeds/                       # synthetic fixtures only
│   ├── models/
│   └── tests/
└── .github/
    ├── ISSUE_TEMPLATE/
    │   ├── bug_report.yml
    │   ├── feature_request.yml
    │   └── deprecation_tracker.yml
    ├── pull_request_template.md
    ├── PULL_REQUEST_TEMPLATE/maintainer_pull_request_template.md
    └── workflows/
        ├── ci.yml
        ├── fusion.yml
        └── auto-release.yml
```

`dbt_project.yml`:

```yaml
name: 'snowflake_company_data'
version: '0.1.0'
config-version: 2
require-dbt-version: [">=1.10.0", "<3.0.0"]

model-paths: ["models"]
macro-paths: ["macros"]
seed-paths: ["seeds"]
test-paths: ["tests"]
analysis-paths: ["analyses"]
snapshot-paths: ["snapshots"]
clean-targets: ["target", "dbt_packages"]

vars:
  snowflake_company_data:
    # --- location ---
    # NOTE: do NOT declare snoco_database here. If the package declares it as null,
    # var('snoco_database', target.database) resolves to null rather than falling
    # back, because the var is defined. Leave it undeclared and let the
    # var() default in sources.yml do the work. Document it in the README instead.
    # This is why Fivetran never declares <package>_database in their vars block.
    snoco_schema: 'PUBLIC_DATA_FREE'

    # --- per-table identifiers (one per source table) ---
    snoco_company_index_identifier: 'company_index'
    # ... generated from Phase 0 findings

    # --- enablement (single underscore) ---
    snoco_company_enabled: true
    snoco_sec_enabled: true
    snoco_securities_enabled: true
    snoco_geography_enabled: true
    snoco_matching_enabled: false     # off by default, requires user config

    # --- user-facing config (double underscore) ---
    snoco__characteristic_types: []           # [] means "pivot the default set"
    snoco__legal_suffixes: [...]              # for name normalization
    snoco__match_source: null                 # ref or source string
    snoco__match_name_column: 'company_name'
    snoco__match_domain_column: null
    snoco__match_ticker_column: null
    snoco__match_id_column: null
    snoco__match_min_score: 0.90
    snoco__match_max_candidates: 5
    snoco__hierarchy_max_depth: 10
    snoco__source_freshness_enabled: false

    # --- engine escape hatch ---
    deactivate_for_fusion: false

models:
  snowflake_company_data:
    +materialized: table
    +schema: snowflake_company_data
    staging:
      +materialized: view
      +schema: stg_snowflake_company_data
    intermediate:
      +materialized: ephemeral
    matching:
      +materialized: table
```

`packages.yml`: depend on `dbt-labs/dbt_utils` with a wide range only if you actually use it. Prefer zero dependencies. If you need a surrogate key, either take the dependency properly or vendor the macro with a provenance comment in `_macros.yml` the way dbt_artifacts does. Do not silently copy code without attribution.

Write `CLAUDE.md` capturing the naming conventions, the ground rules from section 1, and the layer responsibilities, so future sessions in this repo do not drift.

---

# 4. Phase 2: Sources and staging

`models/staging/src_snowflake_company_data.yml`:

```yaml
version: 2

sources:
  - name: snowflake_company_data
    schema: "{{ var('snoco_schema', 'PUBLIC_DATA_FREE') }}"
    database: "{{ var('snoco_database', 'SNOWFLAKE_PUBLIC_DATA_FREE') }}"
    description: >
      Snowflake Public Data (Free), Marketplace listing GZTSZ290BV255.
      Read-only shared database. The local database name is chosen by the
      consumer at install time, so it must be configured via snoco_database.
    tables:
      - name: company_index
        identifier: "{{ var('snoco_company_index_identifier', 'company_index') }}"
        config:
          enabled: "{{ var('snoco_company_enabled', true) }}"
        description: ...
```

**The database default is `'SNOWFLAKE_PUBLIC_DATA_FREE'`, deliberately not `target.database`.** Fivetran defaults to `target.database` because Fivetran lands data in the user's own warehouse database. Ours is a separate database created from a listing, so `target.database` would resolve to the user's build database, which has no `PUBLIC_DATA_FREE` schema, and the resulting "does not exist or not authorized" error would point at the wrong object. `SNOWFLAKE_PUBLIC_DATA_FREE` is the name Snowflake's own examples use, so it is the most likely correct guess for an unconfigured install. Confirm in the README that this must be overridden when the user named their database something else (mine is `MARKETPLACE_CYBERSYN`).

Freshness: leave it off. If `DISCOVERY.md` showed `LAST_ALTERED` is meaningful, add a commented-out block plus README instructions for enabling it via metadata freshness, gated on `snoco__source_freshness_enabled`. Do not enable it by default. Under Fusion, source freshness is not implemented on all adapters and CI runs with `--no-manage-state`.

Staging models are 1:1 with source tables and do renaming, casting, and nothing else. No joins, no filters that lose rows, no business logic. Use the CTE convention `source` → `renamed` → final select. Keep ARRAY columns as arrays here; flattening happens in intermediate.

Add `not_null` on every key column and `unique` on genuine primary keys only. Per Phase 0, `company_id` is expected to be the only safe unique key on the spine. **Do not put a `unique` test on `lei`** if it is an ARRAY.

---

# 5. Phase 3: Intermediate

This layer exists to resolve three specific structural problems the raw data has. Each gets its own model and its own `DECISIONLOG.md` entry.

**Problem 1: ARRAY-typed identifiers.** `LEI` (and possibly `GLOBAL_TICKERS`) are arrays. Build `int_snoco__company_identifiers_unpivoted` that produces a tidy long table:

| company_id | identifier_type | identifier_value | is_primary |
|---|---|---|---|

with rows for `cik`, `ein`, `lei` (one row per array element via `LATERAL FLATTEN`), `permid`, and any tickers. This single model is the join surface for all downstream enrichment, and it makes the cardinality explicit instead of hiding it in an array.

**Problem 2: EAV characteristics.** `COMPANY_CHARACTERISTICS` stores attributes as `relationship_type` / `value` rows with validity dates. Build two models:

- `int_snoco__company_characteristics_current`: filters to currently-valid rows (end date null or in the future), one row per company and characteristic type. Handle the case where a company has multiple concurrent values for a type; decide and document a deterministic tiebreak.
- `int_snoco__company_characteristics_pivoted`: a wide table driven by `var('snoco__characteristic_types')`. When the var is `[]`, use a sensible default set chosen from the Phase 0 frequency analysis. Generate the pivot with a Jinja loop over the type list, not a hard-coded `PIVOT`, so users can extend it without forking.

**Problem 3: bidirectional relationship edges.** `COMPANY_RELATIONSHIPS` appears to store both the `Parent` and `Subsidiary` direction for the same pair, so naive counting double counts. Build `int_snoco__company_edges` that normalizes to a single canonical direction (parent → child), deduplicates, and preserves validity dates.

**Problem 4: the company-to-security join is not scalar equality.** The official Snowflake sample query joins with `ARRAY_CONTAINS(rship.security_id::VARIANT, openfigi.openfigi_share_class_id)`. dbt's `relationships` test assumes scalar equality and cannot express this. Build `int_snoco__company_security_bridge` that flattens both sides to a scalar join key, so downstream models and referential integrity tests both work normally.

---

# 6. Phase 4: Entity marts

Build these, each with a full `.yml` including a description that starts "Each record represents...", column descriptions, and tests.

| Model | Grain | Notes |
|---|---|---|
| `snoco__companies` | one row per `company_id` | The spine plus pivoted characteristics, primary industry, primary location, and counts (securities, subsidiaries). This is the model most people will use. |
| `snoco__company_identifiers` | company + identifier type + value | Tidy long. The join surface for enrichment. |
| `snoco__company_characteristics` | company + type + value + validity window | Cleaned EAV passthrough with an `is_current` flag. For people who want types you did not pivot. |
| `snoco__company_hierarchy` | one row per parent-child edge | Canonical direction, deduped, with validity dates. |
| `snoco__company_ultimate_parent` | one row per company | Recursive CTE walking to the root. Cap depth at `snoco__hierarchy_max_depth` and handle cycles explicitly; real corporate ownership graphs contain them. Document the cycle policy. |
| `snoco__company_securities` | company + security | From the flattened bridge, joined to the security index for ticker and exchange. |
| `snoco__company_industry` | one row per company | SIC code, description, and the division/major-group rollup from the seed. Source it from whichever of `SEC_CIK_INDEX` or `COMPANY_CHARACTERISTICS` Phase 0 showed has better coverage; if both, prefer the one with coverage and document why. |

`snoco__company_hierarchy` and `snoco__company_ultimate_parent` are **conditional on Phase 0 confirming `COMPANY_RELATIONSHIPS` exists in the free schema.** If it does not, drop both from v0.1.0, note it in `DECISIONLOG.md`, and say plainly in the README that hierarchy is not available on the free tier. Do not fake it from characteristics.

The SIC reference seed (`seeds/snoco_sic_division_reference.csv`) maps 4-digit SIC to major group and division. Build it from the published SEC/OSHA SIC structure. This is the package's clearest value-add over raw SQL against the share, and it is legally safe because SIC is a government classification.

Give every mart a `_key` surrogate column where the grain is composite, and test `unique` on that column rather than reaching for a multi-column test.

---

# 7. Phase 5: Matching layer

Disabled by default via `snoco_matching_enabled: false`, because it requires the user to point it at their own data. Every matching model gets `{{ config(enabled = var('snoco_matching_enabled', false)) }}`. Note there is no `models/matching/` directory: marts live at the root of `models/`, following the layout Fivetran's packages use. See `DECISIONLOG.md`.

Configuration surface: `snoco__match_source` takes a relation string the user supplies (a `ref` or `source` expression), plus column mapping vars for name, domain, ticker, country, and their own row id.

Design:

**Deterministic pass first.** Exact joins on ticker, CIK, EIN, LEI, and normalized domain get score 1.0 and method `'exact_<identifier>'`. These are cheap and unambiguous. Run them before any fuzzy logic.

**Blocking, then fuzzy.** Never cross join against the full spine. Generate a blocking key (first significant token of the normalized name, plus optionally `SOUNDEX`) and only score within blocks. Document the recall tradeoff this creates in `DECISIONLOG.md`.

**Scoring.** Use Snowflake's `JAROWINKLER_SIMILARITY` and `EDITDISTANCE` on the normalized name, and **normalize both to [0,1] where higher is better before comparing to any threshold.** These two functions do not share a scale and neither matches the deterministic pass:

- `JAROWINKLER_SIMILARITY(a, b)` returns an **integer 0 to 100**. Divide by 100.0. If you skip this, every candidate scores at or above `snoco__match_min_score: 0.90` and the matching layer silently returns garbage instead of erroring, which is the worst possible failure mode.
- `EDITDISTANCE(a, b)` returns an **unbounded character count where lower is more similar**. Convert with `1 - editdistance(a,b) / greatest(length(a), length(b))` and floor at 0.

Emit the score alongside the method that produced it, so a user can filter by confidence and by technique. Put a unit test on the score expression that pins the scale; this is exactly the kind of bug that survives code review.

**Two outputs.**
- `snoco__company_match_candidates`: every candidate at or above `snoco__match_min_score`, capped at `snoco__match_max_candidates` per input row, with score and method. This is what someone reviews manually.
- `snoco__company_match`: best match per input row, ties broken deterministically (highest score, then method precedence, then lowest `company_id`) so the model is reproducible across runs. Non-determinism here is a real bug, not a nuisance.

Name normalization lives in `macros/normalize_company_name.sql`: lowercase, strip punctuation, collapse whitespace, remove legal suffixes from `var('snoco__legal_suffixes')` (inc, llc, corp, corporation, ltd, limited, plc, gmbh, ag, sa, nv, bv, ab, oy, pty, co, company, holdings, group, and so on). Make the list a var so users can extend it for their geography. Cover it with unit tests.

---

# 8. Phase 6: Macros

Public macros go in `macros/`, one concept per file, filename equal to the macro name. Private helpers get a leading underscore. Document every macro in `macros/_macros.yml` with `arguments:`.

Minimum set:

- `snoco_enabled_vars(vars)` — AND semantics, defaults true. Eight lines. Vendor this rather than depending on `fivetran_utils`.
- `normalize_company_name(column_expression)` — returns a SQL expression, not a query.
- `get_characteristic_types()` — resolves the var to the effective list, applying the default set when empty.
- `company_match_score(left_col, right_col)` — the scoring expression.
- `blocking_key(column_expression)` — the blocking expression.

Skip `adapter.dispatch` entirely. This is a Snowflake-only package and dispatch scaffolding with a single implementation is noise. Do use `dbt.type_*()` shims.

Watch for `validate_macro_args`, the behavior flag that matures in dbt 1.12.0. dbt will validate call sites against macro signatures, so declare arguments precisely and keep call sites consistent.

---

# 9. Phase 7: Tests

**Generic tests in `.yml`.** `not_null` liberally, `unique` on real primary keys, `accepted_values` on the enumerated columns Phase 0 surfaced (`relationship_type`, `entity_level`), `relationships` only where you have a scalar join key. Nest all arguments under `arguments:`.

**Integration test project.** `integration_tests/` is a full sibling dbt project with `packages.yml` containing only `- local: ../`. Point every `snoco_*_identifier` var at a synthetic seed. This is the trick that makes the package testable without a live share, and it is why the identifier vars exist.

Synthetic fixtures must exercise the hard cases explicitly:

- A company with multiple LEIs (tests array flattening)
- A company with concurrent characteristic values of the same type (tests the tiebreak)
- A three-level ownership chain (tests the recursive walk)
- A deliberate ownership cycle (tests the depth cap)
- A company with no securities, and one with several
- Name pairs designed to sit just above and just below the fuzzy threshold

Seed expected outputs and assert with `dbt_utils.equality` where the shape is stable.

**Unit tests** for the macros, using the dbt-audit-helper pattern: a throwaway wrapper model in `integration_tests/models/unit_test_wrappers/` whose entire body is a macro call, with a `unit_tests:` block supplying `given` rows and `expect` rows. This is the current best practice for macro testing and it is much faster than seed round trips.

**Singular tests** in `integration_tests/tests/`, gated off by default behind `snoco_validation_tests_enabled`:

- Fanout: `snoco__companies` row count equals `stg_snoco__company_index` row count
- Row-count consistency between a dev and a prod build of the same model
- Match determinism: running `snoco__company_match` twice produces identical output

**Declarative CI scenarios** in `integration_tests/ci/test_scenarios.yml`, one named entry per var combination:

```yaml
schema_variable_name: "snoco_schema"
test_scenarios:
  - name: "Default"
    vars: {}
  - name: "Company only"
    vars: {snoco_sec_enabled: false, snoco_securities_enabled: false, snoco_geography_enabled: false}
  - name: "Matching enabled"
    vars: {snoco_matching_enabled: true, snoco__match_source: "ref('sample_accounts')"}
  - name: "Custom characteristics"
    vars: {snoco__characteristic_types: ["sic_description", "hq_country"]}
```

---

# 10. Phase 8: Documentation

**README.md**, in this order:

1. Title, one-line description, badge block left-aligned under the H1 (License, dbt version range, Maintained, PRs)
2. Resources: model count, link to the Marketplace listing, link to the changelog
3. What does this package do
4. **Prerequisites**, and put the two things that actually break people first:
   - Acquire the Snowflake Public Data (Free) listing (`GZTSZ290BV255`). Org-level terms acceptance by ORGADMIN is required before the listing can be obtained.
   - `GRANT IMPORTED PRIVILEGES ON DATABASE <your_db> TO ROLE <your_role>;` By default only the role that created the database can access it. This is the number one setup failure.
5. Install snippet with a version range and the note that ranges capture non-breaking changes automatically
6. Configure database and schema. Show that the local database name is chosen at install time and varies by account.
7. Output schema: `<target_schema>_snowflake_company_data` and `<target_schema>_stg_snowflake_company_data`, with the override snippet
8. Final output tables: a Model / Grain / Description table
9. Enable and disable models
10. The matching layer: full configuration walkthrough with a worked example
11. Warehouse support: Snowflake only, stated plainly
12. **Data and licensing.** The package contains SQL only. It does not include, redistribute, or grant any rights to the underlying data. Users must acquire the listing themselves under Snowflake's terms. Attribute the source agencies (SEC, GLEIF, OpenFIGI, Refinitiv/PermID) and reproduce Snowflake's disclaimer: "Snowflake is not endorsed by or affiliated with any of these providers."
13. Maintenance and contributions

**DECISIONLOG.md.** H2-titled entries on every contested modeling choice. At minimum: the characteristics pivot default set and why; the concurrent-value tiebreak; the canonical hierarchy direction; the cycle policy in the recursive walk; the blocking strategy and its recall tradeoff; the match tiebreak ordering; why staging is views. Link CHANGELOG entries into it. This is the highest-value doc in the repo.

**CHANGELOG.md** in the release-parseable format:

```markdown
# dbt_snowflake_company_data v0.1.0

[PR #1](link) includes the following updates:

## Schema/Data Change
**N new models • 0 possible breaking changes**

| Model | Change type | Old | New | Notes |
| ----- | ----------- | --- | --- | ----- |

## Features
## Under the Hood
## Documentation
## Contributors
```

The version at the top of this file is the source of truth for release automation. Malformed changelog means failed release, which is the constraint that keeps it well-formed.

**Doc blocks** in `models/docs.md` and `models/staging/docs.md` for any column appearing in more than two models (`company_id`, `company_name`, `entity_level`, `relationship_start_date`, and so on). Inline descriptions otherwise. Watch for doc block name collisions with likely consumer projects; duplicate doc block names are a hard error under Fusion. Prefix them if in doubt.

Also write `CONTRIBUTING.md` and `RELEASE.md`. `RELEASE.md` states the semver policy explicitly. While pre-1.0, breaking changes are minor bumps, which is what makes the consumer pin `[">=0.1.0", "<0.2.0"]` correct.

---

# 11. Phase 9: CI and release

**`.github/workflows/ci.yml`** — on pull request, run the integration test project against Snowflake for each scenario in `test_scenarios.yml`. Use an ephemeral schema per run (`snoco_integration_tests_${{ github.run_number }}`) and drop it at the end. Use the `DBT_ENV_SECRET_` prefix on credential env vars so dbt scrubs them from logs. Use `pull_request`, not `pull_request_target`, so repository secrets are structurally unavailable to fork PRs; that is the security guarantee.

**`.github/workflows/fusion.yml`** — a separate lane, not a matrix entry in `ci.yml`. Install Fusion via `curl -fsSL https://public.cdn.getdbt.com/fs/install/install.sh | sh` and run:

```bash
dbt build -x --target snowflake --full-refresh --static-analysis=off --no-manage-state --vars '{"deactivate_for_fusion": true}'
```

The separate lane exists because getting one lane green on both engines is not currently achievable. Wire `deactivate_for_fusion` into any fixture or test that Fusion cannot handle, following dbt-project-evaluator's approach. Two working references worth reading: `dbt-labs/dbt-project-evaluator/.github/workflows/fusion.yml` and `godatadriven/dbt-date` (which has an `integration_tests_fusion` job and is the worked example dbt's own guide points at).

Note that dbt-project-evaluator's fusion lane uses `pull_request_target` with an environment gate for fork PRs, not `pull_request`. I would rather have the stricter trust boundary than warehouse coverage on fork PRs, so use `pull_request` and let maintainers re-run against secrets after review. Say so in a comment in the workflow so the deviation is intentional and legible.

**`.github/workflows/auto-release.yml`** — on merge to main, parse the version from the top of `CHANGELOG.md`, compare to the latest GitHub release, and if they differ, slice the release notes out of the changelog between H1 headers and create a **draft** release. A human publishes. Fivetran's `dbt_package_automations` repo has a working implementation to adapt.

Label-driven triggers rather than push-driven where it makes sense: `docs:ready` regenerates docs, `pre-release` cuts a prerelease. Avoids burning CI on every commit.

**Issue templates.** Bug report should ask for `packages.yml` contents, dbt version, and Snowflake account region, which saves a round trip. Include a deprecation tracker template with a required removal date, so sunsets do not drift.

---

# 12. Phase 10: Pre-publish

Do not submit to the hub the day you finish building. hubcap's best practices were updated on 2026-08-05 specifically to require this:

> Packages SHOULD have been used in the author's own production environment for an extended period of time before being submitted. Packages SHOULD contain git history more extensive than "initial commit", demonstrating changes made based on the author's experience with the package instead of a one-shotted project.

So: commit incrementally with real messages throughout the build, run the package against real data, fix what breaks, and let the git history reflect that.

When ready, produce `PUBLISHING.md` with the checklist:

1. `uvx dbt-autofix deprecations`, commit the result
2. `uvx dbt-autofix packages --dry-run` to check our own dependencies. Keep `--dry-run`; without it the tool rewrites `packages.yml` in place.
3. Fusion lane green
4. LICENSE at root, Apache 2.0, GitHub-detectable
5. Tag bare semver, no `v` prefix. hubcap accepts both but its internal representation is inconsistent, so bare is safer.
6. GitHub release created and published
7. PR to `dbt-labs/hubcap` adding `{"<org>": ["dbt-snowflake-company-data"]}` to `hub.json`. Note the hub URL uses `dbt_project.yml`'s `name:` (`snowflake_company_data`), not the repo name. Consumers pin the former.
8. After it lists, a second PR to `dbt-labs/hub.getdbt.com` setting a real `description` and `assets.logo` in `index.json`. Both default to placeholders and persist across version bumps once set. This is the only way to differentiate the listing.
9. Announce in `#package-ecosystem` on dbt Community Slack
10. Do not publish to PyPI. dbt packages resolve from git tags.

---

# 13. Working style

- Commit at the end of each phase with a real message describing what changed and why.
- When Phase 0 findings contradict this brief, the findings win. Note the contradiction in `DISCOVERY.md` and tell me.
- When you make a modeling choice with a defensible alternative, write it in `DECISIONLOG.md` at the moment you make it, not at the end.
- Show me compiled SQL for anything non-obvious, particularly the recursive hierarchy walk and the matching blocking logic.
- Do not add abstraction for warehouses we do not support or configuration nobody asked for. Every var is a maintenance obligation.

**CHECKPOINT 2** after Phase 4 (entity marts), before starting the matching layer.
**CHECKPOINT 3** after Phase 7 (tests), before documentation.

## COPY TO HERE

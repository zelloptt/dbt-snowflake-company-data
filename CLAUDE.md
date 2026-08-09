# Conventions for `dbt-snowflake-company-data`

Read this before making any change. It exists so sessions do not drift from the decisions already made.

## What this repo is

An open-source dbt package published to the dbt Package Hub as `zelloptt/snowflake_company_data`. It models Snowflake's free public company data (Marketplace listing `GZTSZ290BV255`) and provides a matching layer for joining external records to the company spine.

**The repo is private today and will be made public.** Git history is preserved across that flip. Assume every commit is already public.

## Naming

| Thing | Convention | Example |
|---|---|---|
| Repo | `dbt-snowflake-company-data` | |
| Package (`dbt_project.yml` `name:`) | `snowflake_company_data` | this is what consumers pin |
| Model infix | `snoco` | not `scd`, which reads as "slowly changing dimension" |
| Staging model | `stg_snoco__<source_table>` | `stg_snoco__company_index` |
| Intermediate model | `int_snoco__<description>` | `int_snoco__company_edges` |
| Mart model | `snoco__<entity>` | `snoco__companies` |
| Location and enablement vars | `snoco_<thing>` (single underscore) | `snoco_database`, `snoco_company_enabled` |
| User config vars | `snoco__<thing>` (double underscore) | `snoco__match_min_score` |
| Public macro | bare verb-noun, filename equals macro name | `normalize_company_name.sql` |
| Private macro | leading underscore | `_blocking_key` |

The `snoco` infix is not optional. hubcap's package best practices require disambiguating resource names against nodes likely to already exist in a consumer project.

## Ground rules

1. **The source database is read-only.** Snowflake forbids creating objects in a database created from a listing. Everything materializes into the user's own database. Never target `store_failures` or a snapshot at the share.
2. **Never hard-code a database or schema name.** hubcap makes this a MUST. Everything goes through vars.
3. **Verify column names against the live share before using them.** Public documentation for this dataset is thin and partly wrong. `DISCOVERY.md` is the source of truth. If a column you expected is absent, change the model; do not invent the column.
4. **`require-dbt-version` keeps the `<3.0.0` ceiling.** Fusion is 2.x. Narrowing this costs the hub badge.
5. **Generic test arguments nest under `arguments:`.** Required since dbt 1.10.8.
6. **No `dbt_utils.unique_combination_of_columns`.** dbt-core 1.10.6 broke multi-argument test syntax. For composite grain, build a surrogate key column and test `unique` on it.
7. **Prefer loud failures to silent nulls.** Do not adopt Fivetran's `fill_staging_columns` pattern. Every consumer reads the same share, so a schema change breaks everyone identically and we want to know immediately.
8. **No data in the repo.** Any seed derived from the share is redistribution and Apache 2.0 does not cover it. Integration fixtures must be synthetic. A SIC reference seed is fine because SIC is a US government classification.
9. **Snowflake only.** No `adapter.dispatch` scaffolding. Do use `dbt.type_string()` and friends instead of literal types; it costs nothing.
10. **Views in staging, tables only where real work happens.** dbt's package guidance defaults to views and the spine is only ~100K rows.

## Known traps

- **`JAROWINKLER_SIMILARITY` returns an integer 0 to 100, not 0 to 1.** Divide by 100.0 before comparing to any threshold. Skipping this makes every candidate pass `snoco__match_min_score` and the matching layer silently returns garbage instead of erroring.
- **`EDITDISTANCE` is an unbounded character count where lower is better.** Normalize with `1 - editdistance / greatest(length(a), length(b))` and floor at 0.
- **`var('x', default)` returns null, not the default, if the package declares `x: null`.** This is why `snoco_database` is not declared in `dbt_project.yml`.
- **`LAST_ALTERED` is not a freshness signal.** Snowflake documents it as reflecting DDL and background metadata operations. Source freshness ships off by default.
- **Do not `USE SCHEMA INFORMATION_SCHEMA` on a share-derived database.** Snowflake documents that it can fail. Fully qualified references work fine.
- **`ROW_COUNT` and `BYTES` are often null for share-derived objects**, since Marketplace listings commonly expose secure views. Use real `count(*)`.
- **Never remove a `+schema` key from `dbt_project.yml`.** Every resource this package publishes must resolve to a non-null custom schema name. Many consumer projects override `generate_schema_name` and branch on `custom_schema_name is none`, falling back to deriving a schema from the node's path or file name, which turns `stg_snoco__company_index.sql` into a schema name. Setting `+schema` means that branch is never reached. The root key covers everything under `models:` by inheritance; a new resource type declared outside it needs its own. Change values freely, delete nothing.

## Working style

- Commit at the end of each meaningful unit of work, with a message explaining what and why. hubcap explicitly looks for git history "more extensive than 'initial commit'" as evidence the package was actually used rather than one-shotted.
- Record every non-obvious modeling choice in `DECISIONLOG.md` at the moment you make it.
- Bump the version at the top of `CHANGELOG.md` in the same PR as the change. Release automation parses it and a malformed changelog means a failed release.
- Do not add abstraction for warehouses we do not support or configuration nobody asked for. Every var is a maintenance obligation.

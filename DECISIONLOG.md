# Decision Log

Non-obvious modeling and design choices, with the reasoning that produced them. Written when the choice is made, not afterwards. `CHANGELOG.md` entries link here when a release changes one of these.

Format: one `##` heading per decision, stating the choice, the alternatives considered, and what would make us revisit it.

---

## Model infix is `snoco`

An infix is required: hubcap's package best practices ask packages to disambiguate resource names against nodes likely to already exist in a consumer project.

The obvious abbreviation of `snowflake_company_data` is `scd`, which is unusable. It collides with "slowly changing dimension," a term every data practitioner reads automatically, so `scd__companies` would be actively misleading.

`snoco` is a syllabic contraction of **SNO**wflake **CO**mpanies. It was chosen over the initialism `sfcd` for one reason that matters more than it sounds: **it is pronounceable.** A model prefix gets said out loud in standups, code review, and on calls, for years. "snoco companies" is a phrase; "ess-eff-see-dee companies" is spelling. Prefixes people can say are prefixes people use correctly.

Checked before adopting: no collision with any of the 336 packages on the dbt Package Hub, and no meaning in data vocabulary. ("SnoCo" is regional shorthand for Snohomish County, Washington, which will not mislead anyone reading a dbt model.)

The slight informality is contained. What consumers pin is `zelloptt/snowflake_company_data`, which is entirely dry; the infix is an internal identifier convention.

**Revisit if:** never, realistically. Model names are the package's public interface, and once consumers have written SQL against `snoco__companies`, renaming is a breaking change for everyone. This was the last cheap moment to decide.

---

## `snoco_database` defaults to `SNOWFLAKE_PUBLIC_DATA_FREE`, not `target.database`

Fivetran's packages default source database to `target.database`, which works for them because Fivetran lands data in the user's own warehouse database. Ours does not: the share is a separate database created from a Marketplace listing.

Defaulting to `target.database` would resolve to the user's build database, which has no `PUBLIC_DATA_FREE` schema, and the resulting "does not exist or not authorized" error would name the wrong object and send people down the wrong path. `SNOWFLAKE_PUBLIC_DATA_FREE` is the name Snowflake's own examples use, so it is the best guess for an unconfigured install.

Related: `snoco_database` is deliberately not declared in the package's `vars:` block. dbt resolves `var('x', default)` to null rather than the default when the package declares `x: null`, because the var is then defined.

**Revisit if:** Snowflake standardizes the database name at install time.

---

## Source freshness ships disabled

No `COMPANY_*` table carries a documented load timestamp. The obvious fallback, `LAST_ALTERED` from `INFORMATION_SCHEMA.TABLES`, is not a freshness signal: Snowflake's usage notes describe it as reflecting DDL and background metadata operations rather than data loads. dbt-core issue #12945 (open) separately reports `loaded_at_field` under `config:` being ignored.

Shipping freshness on by default would produce confident, wrong answers. It is available behind `snoco__source_freshness_enabled` for anyone who wants it.

**Revisit if:** Snowflake exposes a load timestamp on the shared tables, or #12945 is resolved and metadata freshness proves reliable on share-derived objects.

---

## No `fill_staging_columns` / schema-drift shim

Fivetran's staging pattern emits `cast(null as <type>) as <column>` when an expected column is missing, so downstream models always compile. That trade makes sense for them: a hard failure across thousands of tenants with per-tenant schema variance is worse than a silently null column.

It does not make sense here. Every consumer of this package reads the *same* share, so a provider schema change breaks everyone identically and simultaneously. We want to find out on the next run, not discover it months later as an all-null column that quietly corrupted a mart.

**Revisit if:** the package ever reads a source with genuine per-consumer schema variance.

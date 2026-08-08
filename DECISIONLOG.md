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

## Development files are excluded from the distribution archive

A dbt package is installed into other people's projects. A Package Hub install
resolves the version from the registry, downloads GitHub's source tarball for
that tag, and untars it directly into the consumer's `dbt_packages/`. Those
tarballs are `git archive` output, so `export-ignore` in `.gitattributes`
decides what a consumer receives.

We measured four widely-used published packages and 59% to 81% of their
shipped bytes are not functional package code: `integration_tests/`,
`.github/`, and in `fivetran/dbt_hubspot`'s case 5.9 MB of committed
`catalog.json` / `manifest.json` / `index.html`. None of the four ships a
`.gitattributes`. This is an unsolved gap in ecosystem practice rather than a
convention we are breaking.

So `integration_tests/`, `.github/`, `docs/`, and the contributor-facing
markdown are `export-ignore`d. `dbt_project.yml`, `packages.yml`, the
configured resource paths, `LICENSE`, `README.md`, and `CHANGELOG.md` ship.
Doing this before any models exist was deliberate: the install surface is much
harder to shrink once consumers depend on it.

**The tradeoff we are accepting:** someone who clicks "Download source" on a
GitHub release, or fetches the codeload tarball by hand, gets a package with no
tests in it. That is the same artifact dbt installs, so it is the correct thing
for it to contain, but it will surprise anyone who expects a source archive to
be the source. Cloning and forking are unaffected and still deliver everything.

A second, smaller cost: a `git:` install clones rather than downloading the
archive, so it ignores `export-ignore` entirely and delivers the full
repository. Hub installs are the majority and are what the README recommends,
so we accept the inconsistency rather than duplicating the exclusion list into
a mechanism that would also apply to clones.

**Revisit if:** GitHub changes the source-tarball endpoint to stop honouring
`export-ignore`, or dbt starts installing hub packages by clone. Either would
silently un-do this, so `docs/INSTALL_FOOTPRINT.md` records how to re-test it.

---

## No `fill_staging_columns` / schema-drift shim

Fivetran's staging pattern emits `cast(null as <type>) as <column>` when an expected column is missing, so downstream models always compile. That trade makes sense for them: a hard failure across thousands of tenants with per-tenant schema variance is worse than a silently null column.

It does not make sense here. Every consumer of this package reads the *same* share, so a provider schema change breaks everyone identically and simultaneously. We want to find out on the next run, not discover it months later as an all-null column that quietly corrupted a mart.

**Revisit if:** the package ever reads a source with genuine per-consumer schema variance.

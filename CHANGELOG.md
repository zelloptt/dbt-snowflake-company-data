# snowflake_company_data v0.1.1

Patch release. No model, column or variable is added, removed or renamed, and
no full refresh is needed.

## Bug Fixes

- **The LEI guard test no longer warns on every build.** Snowflake fixed the
  LEI grouping bug upstream in 2026-11: measured 2026-11-11, no LEI array in
  `COMPANY_INDEX` holds more than one element, so none exceed
  `snoco__max_identifier_array_size`. Against the old baseline of 230,
  `assert_snoco__lei_array_guard_baseline` reported "Oversized LEI arrays
  DECREASED beyond tolerance" on every consumer build. The default
  `snoco__expected_oversized_lei_arrays` is now `0`, so the test warns only if
  oversized arrays come back. If you override this var, set it to your source's
  current count: `0` against the share or a current replica.

## Under the Hood

- `snoco__max_identifier_array_size` stays at 25 as a safety net. With every
  array at size 1 it withholds nothing, and it is what stops a recurrence from
  writing false company-to-LEI rows. See `DECISIONLOG.md`.
- The guard test's fallback default matches the new baseline, and its
  "decreased" message now points at the var rather than suggesting the cap be
  removed.

## Documentation

- `docs/DISCOVERY.md` trap 1 is marked fixed by the provider as of 2026-11,
  with re-measured counts beside the original ones, which stay as history. It
  also records that 1,312 LEIs still sit on more than one company, a different
  shape the array cap cannot see.
- The `snoco_lei` doc block and the `lei` / `lei_array` column descriptions no
  longer describe the 5,287-element shared array as current.
- The README's git install example pins `revision: 0.1.1`.

# snowflake_company_data v0.1.0

Initial release. Not yet published to the dbt Package Hub.

## Features

- Repository scaffold, package configuration, and contribution tooling.
- **The models.** Nine staging models over the free share's company graph, three
  intermediate models, and five marts: `snoco__companies` (2.9M rows, one per
  company), `snoco__company_identifiers`, `snoco__company_domains`,
  `snoco__company_securities`, and `snoco__company_hierarchy`.
- **Matching layer**, off by default. `snoco__company_match_candidates` keeps
  every plausible company with its evidence; `snoco__company_match` picks one
  winner per input row. Deterministic domain matching and blocked fuzzy name
  matching, scored separately rather than blended.
- **Macros**: `normalize_company_name`, `normalize_domain` and
  `company_name_similarity`, usable on their own.
- 64 tests, including guards for the three source defects that are silent
  otherwise: oversized identifier arrays, hierarchy recursion truncation, and
  un-normalised similarity scores.
- Doc blocks for the columns that repeat across models, so `company_id` and
  friends are described once.
- **A runnable integration test suite.** `integration_tests/` seeds ten
  synthetic fixtures, builds the package against them and runs 67 tests, with
  no Marketplace listing required. The fixtures are adversarial by design: an
  over-guard LEI array, a company with two parents, an uppercase domain, a name
  that is only a legal form, SEC filers with no company. CI runs it on dbt
  1.10.8 and 1.12.0 plus a Fusion parse lane.

## Bug Fixes

- **Source location defaults changed to `MARKETPLACE_CYBERSYN` / `PUBLIC_DATA_FREE`**,
  the names the listing itself proposes, so an install that accepted the
  suggested database name needs no configuration at all. Previous defaults
  pointed at a private replica and required every consumer to override both.
  **Note `CYBERSYN` is also a schema in this listing and is the wrong one:** it
  is the older Financial Data Package layout and is missing
  `COMPANY_CHARACTERISTICS`, `COMPANY_DOMAIN_RELATIONSHIPS` and `SEC_CIK_INDEX`.
- **`require-dbt-version` floor raised from `>=1.10.0` to `>=1.10.8`.** The
  package's generic tests nest under `arguments:`, which fails on 1.10.0 through
  1.10.7 with `macro 'dbt_macro__test_relationships' takes no keyword argument
  'arguments'`. The old floor advertised support for versions the package does
  not work on. **If you are on dbt below 1.10.8 this package now refuses to
  install, with a message that says so, instead of failing to parse.**
- **Uppercase domains no longer fail deterministic matching.** Domain
  normalisation stripped `www.` before lowercasing, and Snowflake's
  `REGEXP_REPLACE` is case-sensitive, so `WWW.Acme.com` normalised to
  `www.acme.com` and matched nothing. Affected `snoco__company_domains` and the
  matching layer. Now a single `normalize_domain` macro used by both.
- **`snoco__company_securities` no longer fabricates reference rows.** Attributes
  were aggregated per column with `max()`, so a security whose identifier
  appeared in several reference rows could come back with a name, asset class
  and ticker taken from different rows. 10,068 keys have conflicting reference
  rows; the old approach produced 112 combinations that exist nowhere in the
  source. Now one complete row is chosen deterministically.
- **The LEI guard no longer warns on every build.** It fired for any oversized
  array, and the share always contains about 230, so every consumer got a
  permanent warning and `--warn-error` users got a build failure. It now warns
  only on drift from `snoco__expected_oversized_lei_arrays`.

## Under the Hood

- `snoco__company_hierarchy` uses `with recursive` and an explicit column list.
  Snowflake accepts the form without them, but the documented syntax requires
  them and a package should not depend on undocumented tolerance.
- Layout matches the shape the ecosystem has settled on: marts at the root of
  `models/`, with `staging/` and `intermediate/` beneath. Anything at the root
  is a model this package publishes.
- Each source object is addressable by a var (`snoco_company_index` and so on)
  defaulting to its `source()` call, so any single table can be repointed at a
  seed or another relation without touching package code. Lineage is unchanged.
- `require-dbt-version` is `[">=1.10.8", "<3.0.0"]`. The ceiling admits dbt
  Fusion, which reports itself as 2.x; the floor is the first release that
  accepts this package's test syntax (see Bug Fixes).
- Development files are excluded from the distribution archive via `.gitattributes`.
  A Package Hub install untars GitHub's source tarball for the tag straight into
  your `dbt_packages/`, and those tarballs honour `export-ignore`, so
  `integration_tests/`, `.github/`, `docs/` and our contributor documentation
  never land in your project. 38 files ship out of 77 tracked.
- `README.md` links to `DECISIONLOG.md` and `CONTRIBUTING.md` absolutely, so
  those links resolve when the README is read from inside `dbt_packages/`.
- Removed the empty scaffold directories and their `.gitkeep` files. dbt tolerates
  resource paths that are declared in `dbt_project.yml` but absent from disk.
- Corrected the spine size in the README. It said "roughly 100,000 companies";
  it is 2.9 million.
- **`+schema` on every model config is documented as an invariant.** It was
  already set and already load-bearing, just silently: consumer projects that
  override `generate_schema_name` commonly branch on `custom_schema_name is
  none` and fall back to deriving a schema from the node's file name, which
  turns `stg_snoco__company_index.sql` into a schema name. Setting `+schema`
  means that branch is never reached. Now stated at the config block, in the
  README for consumers who override the macro, and in `DECISIONLOG.md`.
- **The replica install is documented as a first-class shape** rather than a
  four-line aside: why the share's secure views cost you a size signal, a
  freshness anchor and control over when the data moves; the `CREATE TABLE ...
  AS SELECT` pattern with a `cloned_at` column; row-count guards; and why the
  replica should stay in one schema.

- **Four literal type casts now use dbt Core's cross-database macros.**
  `cast(null as boolean)` and `cast(... as float)` became
  `{{ dbt.type_boolean() }}` and `{{ dbt.type_float() }}` in `snoco__companies`
  and `snoco__company_match_candidates`. Both macros exist at the `>=1.10.8`
  floor and both render byte-identically on Snowflake, so this is convention
  rather than behaviour. `cast(... as date)` in staging stays literal because
  dbt Core has no `type_date`.

## Documentation

- **The package is audited against hubcap's package best practices**, with the
  result table in `RELEASE.md` beside the submission runbook. Two items are open
  and neither is a code change: hubcap wants a package to have run in the
  author's own production environment before submission, and it recommends
  production-ready packages be at 1.0.0 or above. One SHOULD is deliberately
  deviated from, with the reasoning recorded: cross-database *function* macros
  are not adopted in a package that is Snowflake-only by necessity.
- **Corrected ground rule 2 in `CLAUDE.md`.** It claimed hubcap makes "never
  hard-code a database or schema name" a MUST. hubcap's MUST is narrower and
  concerns table references; database and schema are a SHOULD NOT *assume*,
  which an overridable var satisfies with or without a default. Read literally,
  the old wording argued for deleting the `MARKETPLACE_CYBERSYN` and
  `PUBLIC_DATA_FREE` defaults and re-breaking the zero-config install.
- **Install instructions now use the git form.** The README pinned
  `zelloptt/snowflake_company_data` with a version range, which is Package Hub
  syntax and resolves against `hub.getdbt.com`. The package is not listed there
  yet, so the snippet failed on the listing rather than on the version and no
  git tag repairs it. The README leads with a `git:` + `revision:` install,
  keeps the hub block as the form to switch to once listed, and is explicit that
  a clone ignores `export-ignore` and therefore delivers more than the package.
- `RELEASE.md` described an auto-release workflow that does not exist. The
  release process is manual, and the runbook now says so and gives the actual
  tag and `gh release` commands. It also leads with the point the first build
  attempt tripped over: the tag *is* the release, and a version with no tag
  cannot be installed.

<!--
FORMAT NOTES (delete this block before the first published release)

Release automation parses this file. The rules are load-bearing:

  1. Each release starts with an H1: `# snowflake_company_data vX.Y.Z`
  2. The version at the top of the file is the version that gets released.
  3. Release notes are sliced between one H1 and the next, so do not use H1
     anywhere else.
  4. A malformed header means a failed release. That constraint is what keeps
     this file consistent.

Section order, include only what applies:

  ## Schema/Data Change
  **N new models • M possible breaking changes**

  | Model | Change type | Old | New | Notes |
  | ----- | ----------- | --- | --- | ----- |

  ## Features
  ## Bug Fixes
  ## Breaking Changes
  ## Under the Hood
  ## Documentation
  ## Contributors

If an upgrade requires a full refresh, say so in the section header itself:
  ## Schema/Data Change (--full-refresh required after upgrading)
-->

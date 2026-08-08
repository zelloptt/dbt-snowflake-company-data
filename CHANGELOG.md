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

## Bug Fixes

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
  never land in your project. 36 files ship out of 55 tracked.
- `README.md` links to `DECISIONLOG.md` and `CONTRIBUTING.md` absolutely, so
  those links resolve when the README is read from inside `dbt_packages/`.
- Removed the empty scaffold directories and their `.gitkeep` files. dbt tolerates
  resource paths that are declared in `dbt_project.yml` but absent from disk.
- Corrected the spine size in the README. It said "roughly 100,000 companies";
  it is 2.9 million.

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

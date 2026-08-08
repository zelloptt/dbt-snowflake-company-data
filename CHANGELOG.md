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
- **Macros**: `normalize_company_name` and `company_name_similarity`, usable on
  their own.
- 64 tests, including guards for the three source defects that are silent
  otherwise: oversized identifier arrays, hierarchy recursion truncation, and
  un-normalised similarity scores.

## Under the Hood

- `require-dbt-version` set to `[">=1.10.0", "<3.0.0"]` for dbt Fusion compatibility.
- Development files are excluded from the distribution archive via `.gitattributes`.
  A Package Hub install untars GitHub's source tarball for the tag straight into
  your `dbt_packages/`, and those tarballs honour `export-ignore`, so
  `integration_tests/`, `.github/`, `docs/` and our contributor documentation no
  longer land in your project. You receive 5 files instead of 32.
- `README.md` now links to `DECISIONLOG.md` and `CONTRIBUTING.md` absolutely, so
  those links resolve when the README is read from inside `dbt_packages/`.
- Removed the empty scaffold directories and their `.gitkeep` files. dbt tolerates
  resource paths that are declared in `dbt_project.yml` but absent from disk.

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

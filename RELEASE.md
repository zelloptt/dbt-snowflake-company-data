# Release Process

## Versioning policy

The package is pre-1.0. While on 0.x:

| Change | Bump |
|---|---|
| Breaking change to a model interface, variable name, or macro signature | minor (`0.1.3` → `0.2.0`) |
| New models, new columns, new variables | minor |
| Bug fix with no interface change | patch |

This is the standard 0.x semver convention and it is why the README tells consumers to pin `[">=0.2.0", "<0.3.0"]`. If you change the pin guidance, change this table to match, or you will break people.

At 1.0.0 this switches to conventional semver: breaking changes become major bumps.

## Cutting a release

**The tag is the release.** dbt resolves package versions from git tags, so a
version that exists in `CHANGELOG.md` and `dbt_project.yml` but carries no tag
does not exist to a consumer. `dbt deps` against the pin in the README fails
with no matching version. Nothing else in this runbook matters if the tag is
missing.

There is **no release automation yet**. Every step below is manual and deliberate;
`.github/workflows/` carries the integration test and Fusion lanes and nothing
else. The changelog format rules exist so that automation can be added without
rewriting history, not because something is reading the file today.

1. Confirm CI is green on `main`, including the Fusion lane.
2. Confirm the top of `CHANGELOG.md` carries the new version as an H1 and the notes are complete. **This is the source of truth for the release.** Take the version from here, not from `dbt_project.yml`.
3. Bump `version:` in `dbt_project.yml` and `integration_tests/dbt_project.yml` to match. All three must agree before the tag is cut.
4. Merge to `main`, then tag the merge commit and push the tag:

   ```bash
   git checkout main && git pull
   git tag -a 0.1.0 -m "snowflake_company_data 0.1.0"
   git push origin 0.1.0
   ```

   Tag format is bare semver with no `v` prefix (`0.2.0`, not `v0.2.0`). hubcap accepts both but its internal representation is inconsistent, so bare is safer. Annotated rather than lightweight, so the tag carries an author and a date.
5. Create the GitHub release at that tag with the changelog section as the body:

   ```bash
   gh release create 0.1.0 --title "0.1.0" --notes-file <(sed -n '/^# snowflake_company_data v0.1.0$/,/^# snowflake_company_data v0.0.9$/p' CHANGELOG.md)
   ```

   For the first release there is no next H1 to stop at, so paste the notes by hand or slice to the format-notes comment block.
6. A GitHub release is not required for `dbt deps` to resolve the version, only the tag is. It is required for the Package Hub listing and it is what a human reads, so do it anyway.
7. hubcap indexes hourly and opens a PR against `hub.getdbt.com`. Expect the new version to appear within a business day. Until the package is listed (see below), the tag is still what makes a `git:`-style install work.

## Compliance with hubcap's best practices

[`package-best-practices.md`](https://github.com/dbt-labs/hubcap/blob/main/package-best-practices.md)
is what a hub reviewer checks against. Its key words are RFC 2119, so MUST is a
gate and SHOULD is a recommendation you may deviate from with a reason.

Audited 2026-08-08 against the file as of that date. Re-run this table before
submitting, because the document changes.

| Requirement | Level | State |
|---|---|---|
| Author satisfied with production behaviour at submission | MUST | **Open.** The only item that code cannot close. See below. |
| Used in the author's own production environment for an extended period | SHOULD | **Open.** Same. |
| Git history more extensive than "initial commit" | SHOULD | Met |
| Licence file detectable by GitHub | MUST | Met. `LICENSE` at root; the GitHub API reports `apache-2.0` |
| README explaining getting started and customisation | SHOULD | Met |
| Documentation indicates supported warehouses | SHOULD | Met. "Snowflake only", with the reason |
| No hard-coded table references; `ref`/`source` instead | MUST | Met. Every relation is a CTE, a `ref()`, or a var defaulting to `source()`. Verified by grep: no bare dotted identifier in any `from` or `join` |
| Mechanism to enable/disable subsets | MAY | Met. Five `_enabled` flags |
| Mechanism to customise source table location | SHOULD | Met. `snoco_database`, `snoco_schema`, and a relation var per object |
| Does not assume database/schema names in sources | SHOULD | Met. Both are overridable vars. They carry defaults, which is not the same as assuming; see ground rule 2 in `CLAUDE.md` |
| Assumes table names | MAY | Yes, deliberately. Explicitly permitted, and the objects come from a known listing |
| `require-dbt-version` declared | MUST | Met. `[">=1.10.8", "<3.0.0"]` |
| Allows subsequent minor and patch releases | SHOULD | Met, and wider: the ceiling also admits Fusion's 2.x |
| Dependencies imported from the hub, not git | SHOULD | Not applicable. `packages: []` |
| Widest possible dependency range, no patch pins | SHOULD | Not applicable. Same |
| Does not override dbt Core behaviour affecting other resources | MUST | Met. Five macros, all distinctly named, none of them a dbt hook; vars and model configs namespaced under `snowflake_company_data`; all 13 doc blocks `snoco_`-prefixed |
| Uses dbt Core cross-database macros where available | SHOULD | Partial, deliberately. See below |
| Disambiguated resource names | SHOULD | Met. The `snoco` infix on every model, test, and doc block |
| Git tags validate against hubcap's `version.py` | MUST | `0.1.0` matches the official semver regex hubcap uses |
| Follows Semantic Versioning 2.0.0 | SHOULD | Met |
| Production-ready packages at 1.0.0 or above | SHOULD (note) | **Deviation.** Submitting at 0.1.0; decide before submitting |

### The two open items

Both are the same item: hubcap wants the package to have earned its release.
Nothing in this repo can satisfy them, and they are the reason not to submit on
the day the package is finished.

> Packages SHOULD have been used in the author's own production environment for an extended period of time before being submitted. Packages SHOULD contain git history more extensive than "initial commit", demonstrating changes made based on the author's experience with the package instead of a one-shotted project.

Run it against real data, fix what breaks, and let the commit history reflect
that. The history condition is already met and was met honestly.

### The cross-database macro deviation

hubcap SHOULDs the use of dbt Core's cross-database macros. This package uses
`dbt.type_string()`, `dbt.type_boolean()`, `dbt.type_float()` and `dbt.hash()`,
and does not use `dbt.concat()`, `dbt.length()` or `dbt.split_part()`, writing
`||`, `length()` and `split_part()` directly instead.

The reason is ground rule 9 in `CLAUDE.md`: this package is Snowflake-only by
necessity, because the data source is a Snowflake Marketplace share. A portable
wrapper around a function that will only ever compile for one adapter is
indirection with nothing behind it. Type macros are different and are used
everywhere they apply, because they cost nothing and keep a door open.

`cast(... as date)` in three staging models stays literal because dbt Core has
no `type_date` macro. Verified against dbt-core 1.10.8, the floor: the available
set is `type_bigint`, `type_boolean`, `type_float`, `type_int`, `type_numeric`,
`type_string`, `type_timestamp`.

This is a considered deviation from a SHOULD, which RFC 2119 allows. If a
reviewer pushes back, the swap is mechanical.

### The 1.0.0 question

hubcap notes that production-ready packages should be 1.0.0 or above. This
package is 0.1.0 and the README tells consumers it is pre-1.0 with an interface
that may move.

Both positions are honest; they just cannot both be held at submission. Either
run it in production long enough to mean 1.0.0 and submit at 1.0.0, or submit at
0.x and accept that the listing reads as pre-release. Decide deliberately rather
than by default, and if the answer is 1.0.0, the pin guidance in the versioning
table above changes with it.

## First-time hub submission

0. Re-run the compliance table above against the current
   `package-best-practices.md`, and close the two open items. Everything below
   assumes that passed.
1. `uvx dbt-autofix deprecations`, commit the result.
2. `uvx dbt-autofix packages --dry-run` to check our own dependencies. Keep `--dry-run`; without it the tool rewrites `packages.yml` in place.
3. Confirm the Fusion lane is green.
4. Confirm `LICENSE` is at the repo root and GitHub detects it.
5. Publish a GitHub release at a bare semver tag.
6. Open a PR against [dbt-labs/hubcap](https://github.com/dbt-labs/hubcap) adding `{"zelloptt": ["dbt-snowflake-company-data"]}` to `hub.json`. Note that the hub URL uses `dbt_project.yml`'s `name:` (`snowflake_company_data`), not the repo name, and that is what consumers pin.
7. Complete the hubcap PR template. Ignore its `require-dbt-version` example, which still shows the stale `<2.0.0` ceiling.
8. After listing, open a second PR against [dbt-labs/hub.getdbt.com](https://github.com/dbt-labs/hub.getdbt.com) setting a real `description` and `assets.logo` in `index.json`. Both default to placeholders and persist across version bumps once set, and this is the only way to differentiate the listing.
9. Announce in `#package-ecosystem` on dbt Community Slack.
10. Do not publish to PyPI. dbt packages resolve from git tags.

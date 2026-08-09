# Release Process

## Versioning policy

The package is pre-1.0. While on 0.x:

| Change | Bump |
|---|---|
| Breaking change to a model interface, variable name, or macro signature | minor (`0.1.3` → `0.2.0`) |
| New models, new columns, new variables | minor |
| Bug fix with no interface change | patch |

This is the standard 0.x semver convention and it is why the README tells consumers to pin `[">=0.1.0", "<0.2.0"]`. If you change the pin guidance, change this table to match, or you will break people.

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

## Before the first public release

Do not submit to the dbt Package Hub the day the package is finished. hubcap's best practices, updated 2026-08-05, require:

> Packages SHOULD have been used in the author's own production environment for an extended period of time before being submitted. Packages SHOULD contain git history more extensive than "initial commit", demonstrating changes made based on the author's experience with the package instead of a one-shotted project.

So: run it against real data, fix what breaks, and let the commit history reflect that.

## First-time hub submission

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

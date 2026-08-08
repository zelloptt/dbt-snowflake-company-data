<!--
Before marking ready for review:
  - dbt build --full-refresh && dbt test passes in integration_tests
  - The Fusion lane passes
  - No credentials, no real customer data, no data derived from the share
  - CHANGELOG.md updated
-->

## Summary

<!-- What changed and why. Lead with the why. -->

Resolves #

## Changes

<!-- Bullets. Note anything that changes a model interface, a variable name, or a macro signature. -->

-

## Validation

<!-- How you know this works. Compiled SQL, row counts before/after, screenshots of test output. -->

-

## Checklist

- [ ] `CHANGELOG.md` updated under the target version
- [ ] `version:` bumped in `dbt_project.yml` and `integration_tests/dbt_project.yml` if releasing
- [ ] New or changed models have descriptions, column docs, and grain tests
- [ ] Non-obvious modeling choices recorded in `DECISIONLOG.md`
- [ ] No credentials, connection details, or share-derived data added
- [ ] README updated if this changes configuration or output

# Contributing

Thanks for your interest. Issues and pull requests are both welcome.

## Before you start

- For anything beyond a typo, open an issue first so we can agree on the approach before you spend time on it.
- This package targets **Snowflake only**. Proposals to support other warehouses will be declined, since the data source is a Snowflake Marketplace share.

## Development setup

You need a Snowflake account with the [Snowflake Public Data (Free)](https://app.snowflake.com/marketplace/listing/GZTSZ290BV255) listing installed and granted to your role. See the [README prerequisites](README.md#prerequisites).

```bash
git clone https://github.com/zelloptt/dbt-snowflake-company-data.git
cd dbt-snowflake-company-data/integration_tests
cp profiles.yml.example profiles.yml   # gitignored; fill in your own connection
dbt deps
dbt build --target snowflake
```

`integration_tests/` is a full dbt project that installs the package from `../`. Every source is repointed at a synthetic seed, so the test suite does not depend on live share data.

## Standards

**Never commit credentials.** `profiles.yml`, `.env` files, and `*.p8` key files are gitignored. This repository is public; anything committed stays in history permanently.

**Fixtures must be synthetic.** Seeds derived from the Snowflake share would constitute redistribution and are not covered by our license. Generate fake companies.

**Read [CLAUDE.md](CLAUDE.md).** It documents the naming conventions, ground rules, and the known traps in this dataset. It applies to human contributors too.

**Every model needs:**

- A description starting "Each record represents..."
- Column-level descriptions, using doc blocks for anything appearing in more than two models
- Tests on its grain: `not_null` on keys, `unique` on the primary key or a surrogate key where the grain is composite

**Every non-obvious modeling choice needs an entry in [DECISIONLOG.md](DECISIONLOG.md)**, written when you make the choice rather than afterwards.

## Pull requests

- Target `main`. Squash merge is the default.
- Add a `CHANGELOG.md` entry under the version you are releasing into. Release automation parses this file; a malformed entry breaks the release.
- Fill in the PR template, including how you validated the change.
- CI must pass, including the Fusion lane.

## Reporting bugs

Open an issue using the bug report template. Include your `packages.yml` block, your dbt version, and the compiled SQL if you have it. That combination resolves most reports without a round trip.

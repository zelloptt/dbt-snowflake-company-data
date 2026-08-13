# Contributing

Thanks for your interest. Issues and pull requests are both welcome.

## Before you start

- For anything beyond a typo, open an issue first so we can agree on the approach before you spend time on it.
- This package targets **Snowflake only**. Proposals to support other warehouses will be declined, since the data source is a Snowflake Marketplace share.

## Development setup

**You do not need the Marketplace listing to work on this package.** The test
suite runs entirely on synthetic fixtures, so all you need is a Snowflake
account you can create a schema in. That is deliberate: the share cannot be
redistributed, so fixtures have to be invented anyway, and inventing them means
we can put the awkward cases in on purpose.

You need **dbt 1.10.8 or newer**. This is not a soft floor. Below it, dbt
rejects the `arguments:` property these tests use and you will see
`macro 'dbt_macro__test_relationships' takes no keyword argument 'arguments'`.

```bash
git clone https://github.com/zelloptt/dbt-snowflake-company-data.git
cd dbt-snowflake-company-data/integration_tests

cp profiles.yml.example profiles.yml   # gitignored; fill in your own connection
export DBT_PROFILES_DIR=.

dbt deps                               # installs the package from ../
dbt build                              # seeds, models, and every test
```

`dbt build` seeds ten fixture tables, builds the package end to end against
them, and runs 67 tests. It takes well under a minute; the fixtures are eight
companies.

If you *do* have the listing and want to run against real data, point a scratch
project at it instead. Do not repoint the integration tests: their assertions
encode exact row counts.

### How the fixtures reach the package

The package addresses every source through a var that defaults to its `source()`
call, so `integration_tests/dbt_project.yml` repoints all nine at fixtures
without changing a line of package code:

```yaml
vars:
  snowflake_company_data:
    snoco_company_index: "{{ ref('input_company_index') }}"
    snoco_sec_cik_index: "{{ ref('input_sec_cik_index') }}"
    # ...and so on
```

Five point straight at a seed. Four go through a thin `input_*` model first.
Three of those exist because their real columns are ARRAY-typed and a CSV
cannot express an ARRAY. `input_sec_cik_index` exists because the same CSV
has to hold both a NULL `company_id` (orphan filers) and a literal empty
string in `country`/`state` (trap 8), which one `empty_as_null` setting
cannot express.

### The fixtures are adversarial on purpose

Each one exists to hold a trap the package has to survive. If you change a
fixture and a test fails, read the assertion before you change the expectation:

| Fixture | Encodes |
|---|---|
| `C7` with 30 LEIs | array over `snoco__max_identifier_array_size`, must be withheld |
| `C5` with two `lei` rows at different dates | EAV pivot must pick the later one deterministically |
| `C4` with two parents | hierarchy is a DAG, `company_id` is not unique |
| `C4` domain `HTTPS://WWW.AuroraRobotics.MX/contacto` | uppercase host must normalise; this silently failed once |
| `C6` named `Inc.` | a name that is only a legal form must normalise to NULL |
| Two `sec_cik_index` rows with no `company_id` | 28.7% of the real object; must survive staging |
| `BBG000UNKNOWN` | referenced but undescribed security must be `is_resolved = false` |
| `shared-registrar.com` on two companies | shared domains must be flagged, not dropped |
| `C1` SEC country `X1`, EAV country `US` | EDGAR wins; ISO comes from geography, not from the leaked EAV value |
| `C5` SEC country and state `''` | empty strings must fall through to EAV, not mask it |
| `C8` SEC country `xx` | XX placeholder must become NULL; geography still resolves |

## Standards

**Never commit credentials.** `profiles.yml`, `.env` files, and `*.p8` key files are gitignored. This repository is public; anything committed stays in history permanently.

**Fixtures must be synthetic.** Seeds derived from the Snowflake share would constitute redistribution and are not covered by our license. Every company in `integration_tests/seeds/` is invented.

**Read [CLAUDE.md](CLAUDE.md).** It documents the naming conventions, ground rules, and the known traps in this dataset. It applies to human contributors too, and [docs/DISCOVERY.md](docs/DISCOVERY.md) is the measured source of truth for column names and shapes.

**Every model needs:**

- A schema YAML file next to it, same name, prefixed with an underscore
  (`snoco__companies.sql` → `_snoco__companies.yml`). Do not bundle several
  models into one `_models.yml`; those files grow until the description you
  want is unfindable.
- A description starting "Each record represents..."
- Column-level descriptions, using doc blocks in `models/docs.md` for anything appearing in more than two models
- Tests on its grain: `not_null` on keys, `unique` on the primary key or a surrogate key where the grain is composite
- Generic test arguments nested under `arguments:` (required from dbt 1.10.8)

**Every non-obvious modeling choice needs an entry in [DECISIONLOG.md](DECISIONLOG.md)**, written when you make the choice rather than afterwards.

**Add a fixture case with the fix.** A bug that reached a model can reach it
again. The uppercase-domain and multi-parent cases above are both there because
they shipped broken once.

## Pull requests

- Target `main`. Squash merge is the default.
- Add a `CHANGELOG.md` entry under the version you are releasing into. Release automation parses this file; a malformed entry breaks the release.
- Fill in the PR template, including how you validated the change.
- CI must pass: `integration-tests` (dbt 1.10.8 and 1.12.0) and `fusion`.

### A note on CI

Two lanes, and the split matters if you are contributing from a fork.

**The required checks need no credentials.** `integration-tests` installs dbt at
both ends of the supported range (1.10.8 and 1.12.0), runs `dbt deps` and
`dbt parse`, and asserts the package is fully wired: model, test and macro
counts above their floors, and no package model reading a `source()` instead of
a fixture. `fusion` does the same under the dbt Fusion engine. Both pass on a
fork PR, because GitHub does not give secrets to those and a required check that
needs them would lock every outside contributor out permanently.

This lane catches most of what actually breaks: Jinja and YAML errors, macro
signature validation, ref and source resolution, and version incompatibilities.
It is the lane that would have caught the `require-dbt-version` floor being
wrong.

**The warehouse lane executes SQL and is not required.** `warehouse build` runs
`dbt build` for real against Snowflake, so it only runs on pushes to `main` and
on PRs raised from a branch in this repository. It needs six repository secrets
(`SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PASSWORD`, `SNOWFLAKE_ROLE`,
`SNOWFLAKE_DATABASE`, `SNOWFLAKE_WAREHOUSE`), builds into `snoco_ci_<run_id>`
and drops it afterwards. Without those secrets it skips with a loud warning
rather than failing, and the job summary says so, because a silent skip would
read as "the tests passed".

So: a green PR means the package parses everywhere it claims to. It does not by
itself mean the SQL ran. Run `dbt build` locally, which is the point of the
fixtures needing no Marketplace listing.

## Reporting bugs

Open an issue using the bug report template. Include your `packages.yml` block, your dbt version, and the compiled SQL if you have it. That combination resolves most reports without a round trip.

# Package Audit

Audit of this repo against dbt Labs' published packaging guidance.

**First written 2026-08-08 against a scaffold with no models. Re-verified the
same day after the models landed.** Rows that previously read N/A because there
was nothing to check have been re-evaluated against the real package. Where this
audit got something wrong the first time, it says so rather than quietly
correcting itself.

Sources read: [hubcap package best practices](https://github.com/dbt-labs/hubcap/blob/main/package-best-practices.md)
(fetched verbatim), [Building dbt packages](https://docs.getdbt.com/guides/building-packages),
[Packages](https://docs.getdbt.com/docs/build/packages),
[require-dbt-version](https://docs.getdbt.com/reference/project-configs/require-dbt-version),
[Fusion package compatibility](https://docs.getdbt.com/guides/fusion-package-compat),
[So You Want to Build a Package](https://docs.getdbt.com/blog/so-you-want-to-build-a-package),
[Behavior changes](https://docs.getdbt.com/reference/global-configs/behavior-changes).

Tested against dbt-core 1.12.0 / dbt-snowflake 1.10.8 and dbt-fusion
2.0.0-preview.204. Install-mechanics evidence is in `INSTALL_FOOTPRINT.md`.

Severity: **HIGH** blocks a hub listing · **MED** should be fixed before the
first release · **LOW** worth doing · **INFO** noted, no action proposed.

---

## 1. hubcap best practices: every MUST

| # | Requirement | Verdict | Evidence |
|---|---|---|---|
| 1 | Licence file detectable by GitHub | **PASS** | `LICENSE`, 201 lines, unmodified Apache 2.0 text, `Copyright 2026 Zello, Inc.` at line 189, no `[yyyy]`/`[name]` placeholders. Not `export-ignore`d, so it ships. |
| 2 | MUST NOT hard-code table references; MUST use `ref`/`source` | **PASS** | Re-checked with 20 models present. Every source read goes through a `snoco_*` var defaulting to `source()`; every inter-model read is `ref()`. No literal relation anywhere in `models/`. |
| 3 | MUST declare `require-dbt-version` | **PASS, after a correction** | Now `[">=1.10.8", "<3.0.0"]`. **This audit originally passed the floor at `>=1.10.0` on syntax alone, which was wrong.** The package's generic tests nest under `arguments:`, which fails on 1.10.0 through 1.10.7 with `macro 'dbt_macro__test_relationships' takes no keyword argument 'arguments'`. Reproduced on 1.10.7, clean on 1.10.8. Checking that a version string parses is not the same as checking the package works on it. |
| 4 | MUST NOT override dbt Core behaviour affecting non-package resources | **PASS** | Four macros, all `snoco`-scoped helpers returning SQL fragments. None is a dispatch override, a materialisation, or a redefinition of a built-in. |
| 5 | Git tags MUST validate against hubcap `version.py` | **PASS** | Regex is the official semver one, with a leading `v` stripped before matching. Bare `0.1.0` validates. `RELEASE.md:24` ("bare semver, no `v` prefix") is correct. |

**No MUST is failed.**

## 2. hubcap best practices: SHOULDs

| # | Requirement | Verdict | Notes |
|---|---|---|---|
| 6 | Allow all later minors/patches of that major (`<2.0.0` in their example) | **DEVIATION, deliberate** | We ship `<3.0.0`. hubcap's example predates Fusion, which reports as 2.x. Confirmed current dbt Labs practice: `dbt-labs/dbt_utils` 1.4.1 itself publishes `[">=1.3.0", "<3.0.0"]`. Already documented at `dbt_project.yml:5-8` and `RELEASE.md:43`. **No action.** |
| 7 | Used in production first; git history more than "initial commit" | **GAP, open** | One real commit at session start, seventeen now, spanning discovery, models, a review response and two self-corrections. Models have been built and verified against the real 2.9M-row share. Still not *run in production over time*, which is what the guidance actually asks for. **Remains the binding constraint on a first hub submission.** |
| 8 | README explains getting started and customisation | **PASS** | Prerequisites, Install, Configure, output schemas, enable/disable, matching. |
| 9 | Docs state which warehouses work | **PASS** | `README.md:35-37`, "Snowflake only", with the reason. |
| 10 | Mechanism to customise source table location | **PASS** | `snoco_database` / `snoco_schema` plus a per-object relation var. Sources file exists and is exercised. See finding 3 in section 5 for the separate question of whether the *defaults* are appropriate for a public package. |
| 11 | SHOULD NOT assume database/schema names in sources | **PASS mechanically, DISPUTED in substance** | Nothing is hard-coded; both are vars. But the shipped defaults name the maintainers' own database and schema, so an unconfigured install queries an internal relation rather than failing on an obviously-unset value. Deliberate and owner-directed; flagged as finding 3. |
| 12 | Import dependencies from the hub, not git | **PASS (vacuous)** | `packages: []`. |
| 13 | Widest version range; no patch pins | **PASS (vacuous)** | Same. |
| 14 | Use dbt's cross-database macros | **PASS** | Re-checked against real code: every cast uses `dbt.type_string()` and every surrogate key uses `dbt.hash()`. No literal `varchar` or `md5(` in `models/`. |
| 15 | Disambiguate resource names | **PASS** | `snoco` infix, applied to models, macros and vars. Rationale in `DECISIONLOG.md`. |
| 16 | Semver; production-ready SHOULD be ≥ 1.0.0 | **PASS with note** | 0.1.0, pre-1.0 stated in the README banner and governed by `RELEASE.md`'s 0.x bump table. |

## 3. The five repo-specific claims

Each was treated as unverified until executed.

### 3.1 `require-dbt-version`: **CEILING CONFIRMED, FLOOR WAS WRONG**

The original check ran `dbt_common.semver.versions_compatible` over the bound
and confirmed 1.10.0 was admitted and 1.9.9 and 3.0.0 were not. That is a test
of the range arithmetic, and it passed. It is not a test of whether the package
works on the versions the range admits, and that distinction is the whole
finding: **the package failed on every version from 1.10.0 to 1.10.7.**

Re-tested by installing each engine and parsing the package as an installed
dependency:

| dbt version | Range admits | Package actually parses |
|---|---|---|
| 1.10.7 | no, since the fix | **no**: `macro 'dbt_macro__test_relationships' takes no keyword argument 'arguments'` |
| 1.10.8 | yes | **yes** |
| 1.12.0 | yes | **yes** |
| 2.0.0-preview.204 (Fusion) | yes | **yes**, `dbt deps` and `dbt parse` both succeed |

Floor raised to `>=1.10.8`. A consumer on 1.10.7 now gets "This version of dbt
is not supported with the 'snowflake_company_data' package" rather than a macro
error naming dbt internals.

The ceiling is confirmed as it always was: Fusion reports 2.x, installs, and
parses the package.

### 3.2 `sfcd`-era naming is gone: **CONFIRMED**

Two matches repo-wide, both in `DECISIONLOG.md`, both explaining why `sfcd`
and `scd` were rejected. Those are the record of the decision, not stragglers.
No `sfcd` in any config, path, or identifier.

### 3.3 `snoco_database` undeclared, `var()` default reachable: **CONFIRMED, and the trap is real**

*(The literal default has since changed from `SNOWFLAKE_PUBLIC_DATA_FREE` to the
maintainers' replica. The mechanism below is unaffected.)*

Resolved inside a package model installed into a consumer project:

| var | Declared in package? | `var(x, 'DEFAULT')` resolves to |
|---|---|---|
| `snoco_database` | no | `DEFAULT`, **default reachable** |
| `snoco__match_source` | yes, as `null` | `None`, **default NOT reachable** |
| `snoco_schema` | yes | its declared value |
| `snoco_company_enabled` | yes, `true` | `True` |

`CLAUDE.md`'s known trap holds exactly as written on dbt-core 1.12.0. The
comment at `dbt_project.yml:22-31` is accurate.

That caveat is now closed: the sources file exists and reads both vars.

Also verified, since the README depends on it, the documented consumer
configuration form works:

```yaml
vars:
  snowflake_company_data:      # package-scoped, as the README shows
    snoco_database: MY_DB      # -> resolves to MY_DB inside package models
```

A bare global `vars:` block also reaches the package. Package-scoped is the
right recommendation anyway because it cannot collide with another package.

### 3.4 Declared-but-missing paths: **TOLERATED. Acted on.**

`dbt parse` succeeded with `analysis-paths`, `snapshot-paths`, `seed-paths`,
`test-paths` and `macro-paths` all declared in `dbt_project.yml` but absent
from disk. All nine `.gitkeep` placeholders and their empty directories were
therefore deleted; git recreates each the moment a real file lands.

**INFO:** all six path declarations restate dbt's own defaults
(`config/project.py:455-467`), so they carry no information. Only
`clean-targets` differs from the default by adding `dbt_packages`. Not
proposing removal, since they are conventional and self-documenting, but they are
not load-bearing.

### 3.5 `dbt parse` succeeds: **CONFIRMED**

On dbt-core 1.12.0 and dbt-fusion 2.0.0-preview.204, both as the root project
and as an installed dependency, from the minimised archive.

## 4. Behaviour-change flags

Read from the shipped defaults in `dbt/contracts/project.py`, not from the docs
table, which lags.

| Flag | Default in 1.12.0 | Consequence here |
|---|---|---|
| `require_generic_test_arguments_property` | **True** | `CLAUDE.md` ground rule 5 confirmed. Generic test arguments must nest under `arguments:`. |
| `validate_macro_args` | **True** | The published docs table still shows this as default-false. It is on, and the package's four macros parse under it on 1.10.8, 1.10.15 and 1.12.0. |
| `require_unique_project_resource_names` | False | Not yet enforced; the `snoco` infix satisfies it pre-emptively. |
| `require_ref_searches_node_package_before_root` | False | Worth watching now that models `ref()` each other. Every `ref()` target is `snoco`-prefixed, so a consumer collision is unlikely either way. |

## 5. Findings not in the original brief

| Severity | Finding | Status |
|---|---|---|
| **MED** | `CONTRIBUTING.md:45` requires "CI must pass, including the Fusion lane" and `RELEASE.md:19` says "Confirm CI is green on `main`". There is no `.github/workflows/` directory. Both documents promise a gate that does not exist. | **Open.** Out of scope for this session (no code to test yet), but it must land before the first release or the runbook is fiction. |
| **MED** | `README.md` linked `DECISIONLOG.md` and `CONTRIBUTING.md` relatively. Neither ships, so both 404 for the person most likely to click them: someone reading the README inside their own `dbt_packages/`. | **Fixed.** Both are now absolute GitHub URLs. |
| **LOW** | `RELEASE.md:21` instructs bumping the version in `integration_tests/dbt_project.yml`. That file does not exist. | **Open.** A landmine in the release runbook; resolves itself when the integration project is built. |
| **LOW** | `deactivate_for_fusion` (`dbt_project.yml:75`) is the one var that follows neither the `snoco_` nor the `snoco__` convention in `CLAUDE.md`'s naming table, and it is declared in the *package's* vars. dbt Labs declare it in the *integration test project's* vars instead (`dbt-project-evaluator`). | **Verified working, no change made.** Tested: a global `--vars '{"deactivate_for_fusion": true}'` **does** override the package-scoped declaration, which is exactly how `run_fusion_tests.sh` invokes it. The escape hatch functions. Worth either moving it to `integration_tests/dbt_project.yml` when that exists, or noting the deliberate exception in `CLAUDE.md`. |
| **INFO** | CLI `--vars` is always global. `--vars '{"snowflake_company_data": {"x": true}}'` silently does nothing. It defines a global var *named* `snowflake_company_data`. Package scoping only works in `dbt_project.yml`. | Verified. Worth knowing before writing the CI lane. |
| **INFO** | The reasoning at `dbt_project.yml:22-31` for leaving `snoco_database` undeclared rules out declaring it as `null`, which is correct. It does not rule out declaring it with a real value, which would also work and would put the default where users look. | Not changed. `CLAUDE.md` states the current choice as settled; raising it only so the alternative is on the record. |
| **INFO** | `.github/CODEOWNERS:15` assigns `/.github/workflows/`, which does not exist yet. | Harmless; correct once CI lands. |

## 5a. Findings from external review, 2026-08-08

An independent review of the built package raised 11 issues. Each was verified
by execution before being accepted or rejected.

| # | Finding | Verdict | Status |
|---|---|---|---|
| 1 | Recursive CTE lacks the column list Snowflake requires, so the hierarchy will not compile | **NOT REPRODUCED** | The model compiles and runs: 713 rows, 424 of them produced by the recursive branch, re-run from scratch to confirm. Snowflake accepts the anchor/recursive form without `RECURSIVE` or a column list, despite the documentation specifying them. **Adopted anyway**, because relying on undocumented tolerance in a package other people install is not worth one line saved. |
| 2 | `>=1.10.0` floor is incompatible with the package | **CONFIRMED** | Reproduced on 1.10.7 (`takes no keyword argument 'arguments'`), clean on 1.10.8. Floor raised. The single most valuable finding: this audit passed the floor on syntax alone in section 1. |
| 3 | Defaults point at maintainer infrastructure | **CONFIRMED, owner-directed** | Accurate. The defaults are a deliberate instruction from the repo owner, who accepted the tradeoff explicitly. Escalated rather than changed. |
| 4 | Repo commits an internal Snowflake runbook | **CONFIRMED** | Correct and important: `export-ignore` keeps a file out of the installed package, not out of a public repository, and git history survives the visibility flip. Escalated; needs an owner decision because removal alone does not clear history. |
| 5 | LEI guard warns on every build | **CONFIRMED** | Real design flaw. A test that always fires trains everyone to ignore it, and `--warn-error` turns it into a build failure for every consumer. Replaced with a drift check against a configurable baseline. |
| 6 | `^www\.` stripped before lowercasing | **CONFIRMED** | `WWW.Acme.com` normalised to `www.acme.com`, so it never matched. Present in two models. Fixed by extracting `normalize_domain`, so the package normalises a domain in one place. |
| 7 | Independent `max()` can synthesize a reference row | **CONFIRMED, and reachable** | Measured: 10,278 keys appear in multiple reference rows and 10,068 disagree on at least one attribute. Replaced with `row_number()`/`qualify` picking one complete row. |
| 8 | Integration test project is not runnable | **CONFIRMED** | Already tracked as an open gap. Still open. |
| 9 | README says ten sources, nine declared | **CONFIRMED** | Fixed in README, source YAML and replication notes. |
| 10 | README advertises `_blocking_key` as public | **CONFIRMED** | Fixed: three public macros are `normalize_company_name`, `normalize_domain`, `company_name_similarity`. |
| 11 | Audit and build prompt describe an obsolete package | **CONFIRMED** | This section, and the refreshed rows above, are the response. `BUILD-PROMPT.md` is labelled historical. |

Nine of eleven confirmed. The two that were not accepted as stated are recorded
with the evidence, and one of them was implemented anyway on the reviewer's
reasoning even though the failure did not reproduce.

## 6. Security and hygiene

| Check | Result |
|---|---|
| `.gitignore` blocks credential patterns | **PASS.** All 9 patterns from the brief ignored, plus `.envrc`, `secrets.env`, `service-account-*.json`, `*.pem`, `*.key`, `.user.yml`, `scratch/`, `*.local.sql` |
| Files that must stay trackable | **PASS.** `integration_tests/profiles.yml.example`, `CLAUDE.md`, `integration_tests/package-lock.yml`, `README.md` all trackable |
| Credential-shaped paths ever in history | **NONE** |
| Credential-shaped content in history | **NONE.** The only greps that fire are `env_var()` references in `profiles.yml.example` and the grep command itself quoted inside the old `SETUP.md`. No literal ever committed. |
| Largest blob in history | `BUILD-PROMPT.md`, 37 KB. No data extract. |
| `.github/CODEOWNERS` contains usernames only | **PASS.** `@raphaelvarieras`, no email addresses |

Repo is safe to flip to public on the evidence in history.

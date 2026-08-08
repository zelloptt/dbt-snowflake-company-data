# Package Audit

Audit of this repo against dbt Labs' published packaging guidance, 2026-08-08.

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

## 1. hubcap best practices — every MUST

| # | Requirement | Verdict | Evidence |
|---|---|---|---|
| 1 | Licence file detectable by GitHub | **PASS** | `LICENSE`, 201 lines, unmodified Apache 2.0 text, `Copyright 2026 Zello, Inc.` at line 189, no `[yyyy]`/`[name]` placeholders. Not `export-ignore`d, so it ships. |
| 2 | MUST NOT hard-code table references; MUST use `ref`/`source` | **N/A** | No models exist. `CLAUDE.md` ground rule 2 makes it a standing constraint. Re-check when models land. |
| 3 | MUST declare `require-dbt-version` | **PASS** | `dbt_project.yml:9`, `[">=1.10.0", "<3.0.0"]`. Quoted, no whitespace after operators, which the docs call out as a parse failure. |
| 4 | MUST NOT override dbt Core behaviour affecting non-package resources | **N/A** | No macros exist. |
| 5 | Git tags MUST validate against hubcap `version.py` | **PASS** | Regex is the official semver one, with a leading `v` stripped before matching. Bare `0.1.0` validates. `RELEASE.md:24` ("bare semver, no `v` prefix") is correct. |

**No MUST is failed.**

## 2. hubcap best practices — SHOULDs

| # | Requirement | Verdict | Notes |
|---|---|---|---|
| 6 | Allow all later minors/patches of that major (`<2.0.0` in their example) | **DEVIATION, deliberate** | We ship `<3.0.0`. hubcap's example predates Fusion, which reports as 2.x. Confirmed current dbt Labs practice: `dbt-labs/dbt_utils` 1.4.1 itself publishes `[">=1.3.0", "<3.0.0"]`. Already documented at `dbt_project.yml:5-8` and `RELEASE.md:43`. **No action.** |
| 7 | Used in production first; git history more than "initial commit" | **GAP — open** | One real commit at session start; four now. Nothing has run against real data. **This is the binding constraint on the first hub submission**, not anything in the code. |
| 8 | README explains getting started and customisation | **PASS** | Prerequisites, Install, Configure, output schemas, enable/disable, matching. |
| 9 | Docs state which warehouses work | **PASS** | `README.md:35-37`, "Snowflake only", with the reason. |
| 10 | Mechanism to customise source table location | **PASS (mechanism), PENDING (consumer)** | `snoco_database` / `snoco_schema` verified working end to end. The sources file that reads them does not exist yet. |
| 11 | SHOULD NOT assume database/schema names in sources | **PASS by construction** | No sources yet; `CLAUDE.md` ground rule 2 forbids hard-coding. |
| 12 | Import dependencies from the hub, not git | **PASS (vacuous)** | `packages: []`. |
| 13 | Widest version range; no patch pins | **PASS (vacuous)** | Same. |
| 14 | Use dbt's cross-database macros | **PASS as policy** | `CLAUDE.md` ground rule 9 mandates `dbt.type_string()` and friends. Nothing to check yet. |
| 15 | Disambiguate resource names | **PASS** | `snoco` infix, applied to models, macros and vars. Rationale in `DECISIONLOG.md`. |
| 16 | Semver; production-ready SHOULD be ≥ 1.0.0 | **PASS with note** | 0.1.0, pre-1.0 stated in the README banner and governed by `RELEASE.md`'s 0.x bump table. |

## 3. The five repo-specific claims

Each was treated as unverified until executed.

### 3.1 `require-dbt-version` parses, and the ceiling admits Fusion — **CONFIRMED**

Boundary behaviour, via `dbt_common.semver.versions_compatible`:

| dbt version | Admitted |
|---|---|
| 1.9.9 | no |
| 1.10.0 | **yes** |
| 2.0.0 | **yes** |
| 2.9.9 | **yes** |
| 3.0.0 | no |

Stronger than a parse check: dbt-fusion 2.0.0-preview.204 ran `dbt deps` and
`dbt parse` to success on a consumer project with this package installed.
The ceiling does not merely admit Fusion in theory; Fusion actually installs
and parses the package.

### 3.2 `sfcd`-era naming is gone — **CONFIRMED**

Two matches repo-wide, both in `DECISIONLOG.md`, both explaining why `sfcd`
and `scd` were rejected. Those are the record of the decision, not stragglers.
No `sfcd` in any config, path, or identifier.

### 3.3 `snoco_database` undeclared, `var()` default reachable — **CONFIRMED, and the trap is real**

Resolved inside a package model installed into a consumer project:

| var | Declared in package? | `var(x, 'DEFAULT')` resolves to |
|---|---|---|
| `snoco_database` | no | `DEFAULT` — **default reachable** |
| `snoco__match_source` | yes, as `null` | `None` — **default NOT reachable** |
| `snoco_schema` | yes, `'PUBLIC_DATA_FREE'` | `PUBLIC_DATA_FREE` |
| `snoco_company_enabled` | yes, `true` | `True` |

`CLAUDE.md`'s known trap holds exactly as written on dbt-core 1.12.0. The
comment at `dbt_project.yml:22-31` is accurate.

One caveat on the claim as posed: the sources file whose `var()` default would
be `SNOWFLAKE_PUBLIC_DATA_FREE` does not exist yet, so what was verified is the
mechanism, not that literal.

Also verified, since the README depends on it — the documented consumer
configuration form works:

```yaml
vars:
  snowflake_company_data:      # package-scoped, as the README shows
    snoco_database: MY_DB      # -> resolves to MY_DB inside package models
```

A bare global `vars:` block also reaches the package. Package-scoped is the
right recommendation anyway because it cannot collide with another package.

### 3.4 Declared-but-missing paths — **TOLERATED. Acted on.**

`dbt parse` succeeded with `analysis-paths`, `snapshot-paths`, `seed-paths`,
`test-paths` and `macro-paths` all declared in `dbt_project.yml` but absent
from disk. All nine `.gitkeep` placeholders and their empty directories were
therefore deleted; git recreates each the moment a real file lands.

**INFO:** all six path declarations restate dbt's own defaults
(`config/project.py:455-467`), so they carry no information. Only
`clean-targets` differs from the default by adding `dbt_packages`. Not
proposing removal — they are conventional and self-documenting — but they are
not load-bearing.

### 3.5 `dbt parse` succeeds — **CONFIRMED**

On dbt-core 1.12.0 and dbt-fusion 2.0.0-preview.204, both as the root project
and as an installed dependency, from the minimised archive.

## 4. Behaviour-change flags

Read from the shipped defaults in `dbt/contracts/project.py`, not from the docs
table, which lags.

| Flag | Default in 1.12.0 | Consequence here |
|---|---|---|
| `require_generic_test_arguments_property` | **True** | `CLAUDE.md` ground rule 5 confirmed. Generic test arguments must nest under `arguments:`. |
| `validate_macro_args` | **True** | The published docs table still shows this as default-false. It is on. Macro signatures will be validated once macros land. |
| `require_unique_project_resource_names` | False | Not yet enforced; the `snoco` infix satisfies it pre-emptively. |
| `require_ref_searches_node_package_before_root` | False | No impact while the package has no `ref()`s. |

## 5. Findings not in the original brief

| Severity | Finding | Status |
|---|---|---|
| **MED** | `CONTRIBUTING.md:45` requires "CI must pass, including the Fusion lane" and `RELEASE.md:19` says "Confirm CI is green on `main`". There is no `.github/workflows/` directory. Both documents promise a gate that does not exist. | **Open.** Out of scope for this session (no code to test yet), but it must land before the first release or the runbook is fiction. |
| **MED** | `README.md` linked `DECISIONLOG.md` and `CONTRIBUTING.md` relatively. Neither ships, so both 404 for the person most likely to click them: someone reading the README inside their own `dbt_packages/`. | **Fixed** — both are now absolute GitHub URLs. |
| **LOW** | `RELEASE.md:21` instructs bumping the version in `integration_tests/dbt_project.yml`. That file does not exist. | **Open.** A landmine in the release runbook; resolves itself when the integration project is built. |
| **LOW** | `deactivate_for_fusion` (`dbt_project.yml:75`) is the one var that follows neither the `snoco_` nor the `snoco__` convention in `CLAUDE.md`'s naming table, and it is declared in the *package's* vars. dbt Labs declare it in the *integration test project's* vars instead (`dbt-project-evaluator`). | **Verified working, no change made.** Tested: a global `--vars '{"deactivate_for_fusion": true}'` **does** override the package-scoped declaration, which is exactly how `run_fusion_tests.sh` invokes it. The escape hatch functions. Worth either moving it to `integration_tests/dbt_project.yml` when that exists, or noting the deliberate exception in `CLAUDE.md`. |
| **INFO** | CLI `--vars` is always global. `--vars '{"snowflake_company_data": {"x": true}}'` silently does nothing — it defines a global var *named* `snowflake_company_data`. Package scoping only works in `dbt_project.yml`. | Verified. Worth knowing before writing the CI lane. |
| **INFO** | The reasoning at `dbt_project.yml:22-31` for leaving `snoco_database` undeclared rules out declaring it as `null`, which is correct. It does not rule out declaring it with a real value, which would also work and would put the default where users look. | Not changed. `CLAUDE.md` states the current choice as settled; raising it only so the alternative is on the record. |
| **INFO** | `.github/CODEOWNERS:15` assigns `/.github/workflows/`, which does not exist yet. | Harmless; correct once CI lands. |

## 6. Security and hygiene

| Check | Result |
|---|---|
| `.gitignore` blocks credential patterns | **PASS** — all 9 patterns from the brief ignored, plus `.envrc`, `secrets.env`, `service-account-*.json`, `*.pem`, `*.key`, `.user.yml`, `scratch/`, `*.local.sql` |
| Files that must stay trackable | **PASS** — `integration_tests/profiles.yml.example`, `CLAUDE.md`, `integration_tests/package-lock.yml`, `README.md` all trackable |
| Credential-shaped paths ever in history | **NONE** |
| Credential-shaped content in history | **NONE.** The only greps that fire are `env_var()` references in `profiles.yml.example` and the grep command itself quoted inside the old `SETUP.md`. No literal ever committed. |
| Largest blob in history | `BUILD-PROMPT.md`, 37 KB. No data extract. |
| `.github/CODEOWNERS` contains usernames only | **PASS** — `@raphaelvarieras`, no email addresses |

Repo is safe to flip to public on the evidence in history.

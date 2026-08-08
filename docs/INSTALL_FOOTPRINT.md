# Install Footprint

What a consumer of `zelloptt/snowflake_company_data` actually receives, how that
was determined, and what it costs them.

This file is `export-ignore`d along with the rest of `docs/`, so it does not
ship. It exists so the next person can re-run the checks instead of trusting
them.

Verified on 2026-08-08 against dbt-core 1.12.0 (dbt-snowflake 1.10.8) and
dbt-fusion 2.0.0-preview.204.

**Everything below marked VERIFIED was executed. Everything marked INFERRED was
reasoned from source code that was read but not executed. Nothing here is
recalled from documentation alone.**

---

## Summary

| Claim | Status |
|---|---|
| Hub installs download a tarball rather than cloning | **VERIFIED** |
| That tarball is GitHub's codeload endpoint, and it honours `export-ignore` | **VERIFIED** |
| dbt's Fusion CDN mirror carries an identical file list | **VERIFIED** |
| `git:` installs clone and ignore `export-ignore` entirely | **VERIFIED** |
| `local:` installs symlink the working tree, so local dev is unaffected | **VERIFIED** |
| A `.dbtignore` shipped inside a package **does** take effect, package-scoped | **VERIFIED** (contradicts the assumption we started with) |
| `.dbtignore` cannot reduce install size, only parse surface | **VERIFIED** |
| `packages: []` means zero extra directories in a consumer's `dbt_packages/` | **VERIFIED** |
| dbt tolerates declared-but-missing resource paths | **VERIFIED** |

---

## 1. How dbt installs this package

### 1.1 The hub hands dbt a codeload URL

The registry entry for a package version carries the download location
directly. Using `dbt-labs/dbt_utils` 1.4.1 as a published stand-in:

```bash
curl -sS https://hub.getdbt.com/api/v1/dbt-labs/dbt_utils/1.4.1.json
```

```json
  "downloads": {
    "tarball": "https://codeload.github.com/dbt-labs/dbt-utils/tar.gz/1.4.1",
    "format": "tgz",
    "sha1": "f68fc0a39f37414ac87e5bfbb23b12092a03896f"
  },
  "fusion_compatibility": {
    "parse_compatible": true,
    "fusion_compatible_download": {
      "tarball": "https://public.cdn.getdbt.com/package-hub/dbt-labs_dbt_utils_1.4.1.tar.gz",
      "format": "tgz"
    }
  }
```

Both paths in the hypothesis exist. The codeload URL is the one dbt-core uses;
the CDN URL sits under `fusion_compatibility`.

The recorded `sha1` is the sha1 of the codeload tarball itself:

```bash
curl -sSL https://codeload.github.com/dbt-labs/dbt-utils/tar.gz/1.4.1 -o utils.tgz
shasum -a 1 utils.tgz
# f68fc0a39f37414ac87e5bfbb23b12092a03896f   <- matches the registry exactly
```

That matters more than it looks: the hub is checksumming the archive
*after* `export-ignore` has been applied, so exclusions are part of the
published artifact's identity rather than something applied downstream.

### 1.2 dbt-core downloads that URL and untars it

`dbt/deps/registry.py` → `RegistryPinnedPackage.install` → `PinnedPackage._install`
in `dbt/deps/base.py`:

```python
download_url = metadata.downloads.tarball
...
def download_and_untar(self, download_url, tar_path, deps_path, package_name):
    system.download(download_url, tar_path)
    system.untar_package(tar_path, deps_path, package_name)
```

No clone, no git. **VERIFIED** by reading the installed 1.12.0 source, and
exercised end to end below via `tarball:`, which shares the identical
`download_and_untar` implementation through the same base class.

### 1.3 The codeload tarball honours `export-ignore`

This was the single most important thing to establish and could not be assumed.
Tested against `guzzle/guzzle` 7.9.2, a published repo whose `.gitattributes`
excludes a lot:

```bash
curl -sSL https://raw.githubusercontent.com/guzzle/guzzle/7.9.2/.gitattributes
```
```
.editorconfig          export-ignore
.gitattributes         export-ignore
/.github/              export-ignore
.gitignore             export-ignore
/docs/                 export-ignore
/phpunit.xml.dist      export-ignore
/tests/                export-ignore
...
```

```bash
curl -sSL https://codeload.github.com/guzzle/guzzle/tar.gz/refs/tags/7.9.2 -o guzzle.tar.gz
tar tzf guzzle.tar.gz | sed 's|^[^/]*/||' | grep -v '^src/' | sort
```
```
CHANGELOG.md
LICENSE
README.md
UPGRADING.md
composer.json
```

Every `export-ignore`d path is absent, including `.gitattributes` itself.
93 KB delivered. **VERIFIED.**

### 1.4 The Fusion CDN mirror is the same file set

```bash
curl -sSL https://codeload.github.com/dbt-labs/dbt-utils/tar.gz/1.4.1 -o codeload.tgz
curl -sSL https://public.cdn.getdbt.com/package-hub/dbt-labs_dbt_utils_1.4.1.tar.gz -o cdn.tgz
tar tzf codeload.tgz | sed 's|^[^/]*/||' | sort > a
tar tzf cdn.tgz      | sed 's|^[^/]*/||' | sort > b
diff a b && echo IDENTICAL
```
```
IDENTICAL          # 266 entries each
codeload: 83314 bytes
cdn:      87302 bytes
```

Identical contents; the byte difference is gzip settings, not a different file
set. The CDN is a re-compression of the codeload archive, so it inherits
`export-ignore` rather than bypassing it. **VERIFIED.**

### 1.5 `git:` installs clone, and ignore `export-ignore` entirely

`dbt/deps/git.py` → `GitPinnedPackage._checkout` → `git.clone_and_checkout`.
Confirmed empirically with a throwaway package whose `.gitattributes` excluded
`/integration_tests/`, `/.github/` and `SCRATCH.md`:

```
packages:
  - git: "file:///tmp/.../pkg"
    revision: 0.1.0
```
```
dbt_packages/testpkg/.gitattributes                              <- excluded, still delivered
dbt_packages/testpkg/.github/workflow.yml                        <- excluded, still delivered
dbt_packages/testpkg/SCRATCH.md                                  <- excluded, still delivered
dbt_packages/testpkg/integration_tests/models/pkg_integration_model.sql
dbt_packages/testpkg/dbt_project.yml
dbt_packages/testpkg/macros/pkg_macro.sql
dbt_packages/testpkg/models/staging/pkg_real_model.sql
...
```

**VERIFIED, and it is a real limitation.** Minimisation only benefits hub
consumers. The README recommends the hub install, and hub installs are the
overwhelming majority, so we accept this rather than duplicating the exclusion
list into a mechanism that would also apply to clones.

One mitigating fact from the same run: the shipped `integration_tests/` model
was **not parsed** by the consumer. The manifest contained only
`model.testpkg.pkg_real_model`. dbt searches the configured resource paths
relative to the package root, and `integration_tests/models/` is not one of
them. So shipping `integration_tests/` is a bytes-and-noise problem, never a
correctness problem.

### 1.6 `local:` installs are symlinks, so local development cannot break

`dbt/deps/local.py` → `LocalPinnedPackage.install` calls
`system.make_symlink(src_path, dest_path)`, falling back to `shutil.copytree`
only on `OSError`. Confirmed against this repo's actual `integration_tests/`
project:

```bash
cd integration_tests && dbt deps && ls -la dbt_packages/
```
```
lrwxr-xr-x  snowflake_company_data -> /private/tmp/.../probe
```
```bash
ls dbt_packages/snowflake_company_data/
```
```
CHANGELOG.md CLAUDE.md CONTRIBUTING.md DECISIONLOG.md LICENSE README.md
RELEASE.md analyses dbt_project.yml docs integration_tests macros models
packages.yml seeds snapshots tests
```

The dev install reads the working tree directly and sees every
`export-ignore`d file. `dbt parse` succeeded and resolved package models
alongside the integration project's own. **VERIFIED: `.gitattributes` cannot
break local development.**

### 1.7 `.dbtignore`: the assumption we started with was wrong

The hypothesis was that `.dbtignore` "does not clearly apply to installed
packages." It does apply, and it is scoped per-project.

`dbt/parser/read_files.py`:

```python
def read_files_for_project(self, project, file_types):
    dbt_ignore_spec = generate_dbt_ignore_spec(project.project_root)
```

`read_files_for_project` runs for every project in `all_projects`, which
includes installed packages, and resolves `.dbtignore` against *that project's*
root. Tested by shipping a `.dbtignore` containing `models/staging/` inside a
package:

```
nodes: ['model.consumer.my_model']
VERDICT: package .dbtignore SUPPRESSED the package model
```

The converse also holds. A `.dbtignore` at the **consumer's** root does *not*
reach into `dbt_packages/`:

```
nodes: ['model.consumer.my_model', 'model.testpkg.pkg_real_model']
VERDICT: consumer .dbtignore reaches into dbt_packages: NO (package-local only)
```

**So it works, and we still do not use it**, for two reasons:

1. It controls *parsing*, not *distribution*. The bytes still land on the
   consumer's disk. It cannot substitute for `export-ignore`.
2. For our exclusion set it would be a no-op anyway. dbt only searches the
   configured resource paths, so `integration_tests/`, `.github/` and `docs/`
   are never parsed regardless (see 1.5).

Worth knowing if we ever need to ship a file inside `models/` that dbt must not
parse. Not useful for footprint.

### 1.8 `packages: []` costs a consumer nothing

`packages.yml` here is deliberately empty. Across all three install
mechanisms, exactly one directory appeared under the consumer's
`dbt_packages/`:

```bash
ls consumer/dbt_packages/
# testpkg
```

**VERIFIED.** Recorded as a constraint we are choosing to keep: every
dependency we add becomes a resolution constraint and a directory for every
consumer of this package. `packages.yml` already documents the rules for
breaking this if it ever becomes necessary.

---

## 2. What we now ship

`.gitattributes` at the repo root implements the exclusions. Verified
positively (does everything that should ship survive?) and negatively (does
anything excluded leak?) by adding a probe file to every path in a clone and
archiving it:

```
  SHIPS      models/staging/stg_snoco__probe.sql
  SHIPS      models/staging/_stg_snoco__models.yml
  SHIPS      macros/match/_probe.sql
  SHIPS      seeds/snoco_probe_seed.csv
  SHIPS      tests/generic/probe_test.sql
  SHIPS      snapshots/probe_snap.sql
  SHIPS      analyses/probe_analysis.sql
  SHIPS      dbt_project.yml
  SHIPS      packages.yml
  SHIPS      LICENSE
  SHIPS      README.md
  SHIPS      CHANGELOG.md
  excluded   integration_tests/models/should_not_ship.sql
  excluded   integration_tests/dbt_project.yml
  excluded   .github/workflows/should_not_ship.yml
  excluded   docs/should_not_ship.md
  excluded   docs/BUILD-PROMPT.md
  excluded   CLAUDE.md
  excluded   CONTRIBUTING.md
  excluded   DECISIONLOG.md
  excluded   RELEASE.md
  excluded   .gitattributes
  excluded   .gitignore
```

That archive was then served over HTTP and installed into a consumer project
through dbt's `tarball:` method, which shares `download_and_untar` with the
registry install:

```
19:48:20  Installed from tarball (url: http://localhost:8802/pkg.tar.gz)
19:48:22  Performance info: .../target/perf_info.json
  nodes    : ['analysis.snowflake_company_data.probe_analysis',
              'model.consumer.my_model',
              'model.snowflake_company_data.stg_snoco__probe',
              'seed.snowflake_company_data.snoco_probe_seed',
              'snapshot.snowflake_company_data.probe_snap']
  macros   : ['macro.snowflake_company_data.snoco_probe']
```

Every resource type parsed from the minimised archive. The same project also
parses under Fusion:

```
$ dbt --version
dbt-fusion 2.0.0-preview.204
$ dbt deps && dbt parse
 Installed 1 package
Finished 'parse' successfully for target 'sf' [654ms]
```

---

## 3. Before and after

```bash
git archive --format=tar HEAD | tar t | sort   # what a consumer receives
git archive --format=tar HEAD | gzip -9n | wc -c
git ls-files | wc -l                           # what the repo contains
```

`gzip -9n` rather than `--format=tar.gz`, because gzip embeds a timestamp and
the compressed size otherwise drifts between runs.

| | Tracked files | Files shipped | Uncompressed | tar.gz |
|---|---|---|---|---|
| Scaffold, as received (`1e222b8`) | 32 | 32 | 122,880 B | 32,886 B |
| After hygiene (`1fcdff1`) | 18 | 18 | 102,400 B | 30,559 B |
| Same tree, `.gitattributes` removed | 19 | 18 | 112,640 B | 31,463 B |
| Exclusions in place, before any models | 21 | 5 | 30,720 B | 9,080 B |
| **HEAD, with the models** | **54** | **36** | **153,600 B** | **32,404 B** |

The last row is the one that matters, and it is the whole argument in two
numbers. The repo grew from 21 tracked files to 54. The install grew from 5
files to 36, and **every one of the 31 added files is a model, a macro, a test
or a schema definition.** Not one of the 18 non-shipping files added alongside
them reached a consumer.

Compressed size at HEAD is 32,404 B against the original scaffold's 32,886 B: a
package that now contains 17 models, 3 macros and 64 tests ships slightly
smaller than the empty scaffold did.

Attributed honestly: deleting `SETUP.md`, moving `BUILD-PROMPT.md` and dropping
the `.gitkeep` placeholders accounts for a small part of this. **`.gitattributes`
alone takes 18 shipped files to 5, and 112,640 bytes to 30,720, a 73%
reduction on its own.** Against the original scaffold the total is 84% fewer
files and 75% fewer bytes.

What a consumer receives today:

```
CHANGELOG.md
LICENSE
README.md
dbt_project.yml
packages.yml
```

### The ratio

Measured at HEAD, on the same definition used for the reference packages below:

```
  functional        84.1 KB
  non-functional    23.9 KB   (22%)
```

An earlier revision of this file recorded 83% non-functional and said the number
was meaningless, which it was: there was no code, and `LICENSE` alone is 11 KB
of Apache 2.0 boilerplate we are required to ship. Now that the models exist the
ratio means something, and the shape is what was predicted. The non-functional
part is a near-fixed floor (licence, README, changelog) that grows only as the
prose grows. Everything else added since has been functional.

For comparison, the four reference packages sit between 63% and 92%.

### Against the reference packages

Measured from the actual codeload tarballs, so these are the bytes a consumer
receives. "Functional" is `models/ macros/ seeds/ tests/ snapshots/ analyses/`
plus `dbt_project.yml` and `packages.yml`; everything else is the author's
development concern.

| Package | tar.gz | Extracted | Functional | Non-functional | Files | Biggest non-functional |
|---|---|---|---|---|---|---|
| `dbt-labs/dbt_utils` 1.4.1 | 81 KB | 278 KB | 67 KB | **76%** | 235 | integration_tests 67 KB, README 50 KB, CHANGELOG 41 KB |
| `fivetran/hubspot` 1.9.1 | 1,067 KB | 7,129 KB | 571 KB | **92%** | 458 | **docs 5,894 KB**, integration_tests 514 KB |
| `dbt-labs/dbt_project_evaluator` 1.3.4 | 91 KB | 370 KB | 137 KB | **63%** | 347 | docs 89 KB, integration_tests 50 KB |
| `brooklyn-data/dbt_artifacts` 2.11.0 | 543 KB | 1,112 KB | 320 KB | **71%** | 199 | docs 426 KB, uv.lock 191 KB |
| **`zelloptt/snowflake_company_data`** | **32 KB** | **108 KB** | **84 KB** | **22%** | **36** | LICENSE 11 KB (required) |

These percentages differ somewhat from the ones in the original handoff
because they are computed from the published tarball rather than the repo, and
against the "what dbt parses" definition above. The direction and the
conclusion are the same.

The `fivetran/hubspot` finding is worth stating precisely, because it is the
trap this whole exercise exists to avoid:

```
3556 KB  docs/manifest.json
1776 KB  docs/index.html
 563 KB  docs/catalog.json
```

5.9 MB of committed dbt docs artifacts, 83% of that package's entire install
size, delivered to every consumer on every `dbt deps`. Our `/docs/`
`export-ignore` line exists specifically to make that mistake impossible here.

None of the four reference packages contains a `.gitattributes`.

---

## 4. Re-testing this

The two things that would silently undo all of it:

1. **GitHub stops honouring `export-ignore` on codeload.** Re-run the guzzle
   check in 1.3. If `tests/` appears in that tarball, this document is void.
2. **dbt starts installing hub packages by clone.** Re-read
   `dbt/deps/base.py::_install`; if it no longer calls `download_and_untar`,
   re-verify.

After cutting a release, the direct check is:

```bash
curl -sL https://codeload.github.com/zelloptt/dbt-snowflake-company-data/tar.gz/<tag> | tar tz
```

It should list the shipping set and nothing else. This has not been run
against a real tag yet, because no tag exists. That is the one claim in this
document confirmed only by proxy (guzzle) and by local `git archive`, not
against our own published artifact. **Run it at the first release.**

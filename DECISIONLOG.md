# Decision Log

Non-obvious modeling and design choices, with the reasoning that produced them. Written when the choice is made, not afterwards. `CHANGELOG.md` entries link here when a release changes one of these.

Format: one `##` heading per decision, stating the choice, the alternatives considered, and what would make us revisit it.

---

## Model infix is `snoco`

An infix is required: hubcap's package best practices ask packages to disambiguate resource names against nodes likely to already exist in a consumer project.

The obvious abbreviation of `snowflake_company_data` is `scd`, which is unusable. It collides with "slowly changing dimension," a term every data practitioner reads automatically, so `scd__companies` would be actively misleading.

`snoco` is a syllabic contraction of **SNO**wflake **CO**mpanies. It was chosen over the initialism `sfcd` for one reason that matters more than it sounds: **it is pronounceable.** A model prefix gets said out loud in standups, code review, and on calls, for years. "snoco companies" is a phrase; "ess-eff-see-dee companies" is spelling. Prefixes people can say are prefixes people use correctly.

Checked before adopting: no collision with any of the 336 packages on the dbt Package Hub, and no meaning in data vocabulary. ("SnoCo" is regional shorthand for Snohomish County, Washington, which will not mislead anyone reading a dbt model.)

The slight informality is contained. What consumers pin is `zelloptt/snowflake_company_data`, which is entirely dry; the infix is an internal identifier convention.

**Revisit if:** never, realistically. Model names are the package's public interface, and once consumers have written SQL against `snoco__companies`, renaming is a breaking change for everyone. This was the last cheap moment to decide.

---

## Source location defaults to the name Snowflake proposes

Superseded two earlier positions, both of which were wrong for the same reason:
they optimised for how *we* read the data rather than for how a consumer does.

The first defaulted `snoco_database` to `SNOWFLAKE_PUBLIC_DATA_FREE` on the
reasoning that it is the name Snowflake's examples use. The second pointed both
vars at a private replica, which made an unconfigured public install query a
relation that exists in exactly one account.

The listing suggests `MARKETPLACE_CYBERSYN` at acquisition time, and most people
accept the suggestion. Defaulting to it means the common case needs no
configuration at all, and the uncommon case is a one-line override that the
README shows. Not `target.database`, which is Fivetran's default and right for
them because Fivetran lands data in the user's own database; ours is a separate
database whichever layout you use.

**The schema default is `PUBLIC_DATA_FREE`, and this is the part worth reading.**
The listing exposes two schemas. `CYBERSYN` is the older Financial Data Package
layout and looks like a reasonable default, especially given the database name.
It carries 6 of the 9 objects this package reads. The three it lacks are
`COMPANY_CHARACTERISTICS`, `COMPANY_DOMAIN_RELATIONSHIPS` and `SEC_CIK_INDEX`,
which between them are every company attribute, every domain, and all SIC and
address data. A consumer pointed at `CYBERSYN` would get six staging models that
build and three that fail on a missing object, and the failure names the object
rather than the schema, so the diagnosis is not obvious. Verified by querying
both schemas for all nine objects.

Related, and unchanged: `snoco_database` is deliberately not declared in the
package's `vars:` block. dbt resolves `var('x', default)` to null rather than the
default when the package declares `x: null`, because the var is then defined.
Verified still true on dbt-core 1.12.0.

**Revisit if:** Snowflake changes the suggested database name, or consolidates
the two schemas.

---

## Identifier arrays are capped rather than flattened

`COMPANY_INDEX.LEI` is an ARRAY. The obvious model is a `lateral flatten` into a
long identifier table, and it is a trap: **47 unrelated companies carry the
byte-identical 5,287-element array**, and that pattern repeats at every large
size, one distinct array value shared across every company at that size. 224 of
the 230 affected companies have a slash in the name, so this is a provider-side
grouping bug rather than real ownership.

The argument for the cap is correctness, not volume, and it is worth being
precise because the volume argument is the tempting one and it does not hold up.
Unguarded the flatten produces 333,143 LEI rows against 63,142 guarded. The
270,001 difference would grow the whole identifier table by about 7%, which is
nothing. What matters is that those rows are **false assertions**: a lookup by
one LEI returns 47 companies, at most one of which owns it. A wrong join key is
worse than a missing one, and this one is wrong silently.

`snoco__max_identifier_array_size` (default 25) drops arrays above the cap
**before** the flatten rather than filtering after it, because filtering after
still materialises the explosion. A warn-severity test reports the affected
count on every run, so the number cannot drift silently in either direction: if
the provider fixes the bug, or makes it worse, that count is the only signal.

Considered and rejected: taking the first element. It is cheap and it is a lie,
because there is no ordering in the array that makes the first element the right
one, and a wrong LEI is worse than a missing one.

**Revisit if:** the provider fixes the underlying bug, at which point the cap can
be raised or removed and the test will say so.

---

## The entity-attribute-value pivot deduplicates explicitly

`COMPANY_CHARACTERISTICS` is not unique on `(company_id, relationship_type)`:
11,745,288 rows against 11,471,303 distinct pairs. The natural instinct is to
filter to current records with `where relationship_end_date is null`, and that
is the trap: **`relationship_end_date` is NULL on every one of the 11.7M rows.**
There are no closed records at all, so the filter reads as though it selects
current values while doing nothing.

There are no exact duplicate rows. The excess comes from 1,918 company/attribute
pairs holding more than one distinct value, of which 1,913 are `lei`.

The pivot therefore ranks by `relationship_start_date desc, value` and takes the
first. `max(value)` would also collapse the duplicates and is what a reasonable
person writes first, but it silently prefers the lexically largest value, which
is not the same thing as the most recent one. The explicit tiebreak on `value`
exists so repeated runs return the same answer rather than whatever the scan
order produced.

**Revisit if:** the provider starts populating `relationship_end_date`, which
would make real SCD handling both possible and necessary.

---

## Company-to-security resolves through a flattened lookup, not `ARRAY_CONTAINS`

`COMPANY_SECURITY_RELATIONSHIPS.SECURITY_ID` is one column whose meaning depends
on `SECURITY_ID_TYPE`, and four of the five types resolve against ARRAY columns
on the security indexes. The obvious join is the one the shape suggests:

```sql
array_contains(cs.security_id::variant, ofi.figi_id_array)
```

which is 985,971 rows against 119,273 with no equality to hash on: roughly 117
billion array probes, and a query that does not finish. The reference arrays are
flattened into a `(type, value)` lookup first and joined by equality instead.

Flattening is safe here in a way it is not for LEI. These arrays are genuinely
multi-valued, since one security really does carry a FIGI per exchange, and they
are bounded: the largest holds 707 entries and the whole lookup is about 2.6M
rows. Applying the LEI-style cap here would silently drop real securities, so it
is deliberately absent.

**Revisit if:** the reference arrays stop being bounded.

---

## Source freshness ships disabled

No `COMPANY_*` table carries a documented load timestamp. The obvious fallback, `LAST_ALTERED` from `INFORMATION_SCHEMA.TABLES`, is not a freshness signal: Snowflake's usage notes describe it as reflecting DDL and background metadata operations rather than data loads. dbt-core issue #12945 (open) separately reports `loaded_at_field` under `config:` being ignored.

Shipping freshness on by default would produce confident, wrong answers. It is available behind `snoco__source_freshness_enabled` for anyone who wants it.

**Revisit if:** Snowflake exposes a load timestamp on the shared tables, or #12945 is resolved and metadata freshness proves reliable on share-derived objects.

---

## Development files are excluded from the distribution archive

A dbt package is installed into other people's projects. A Package Hub install
resolves the version from the registry, downloads GitHub's source tarball for
that tag, and untars it directly into the consumer's `dbt_packages/`. Those
tarballs are `git archive` output, so `export-ignore` in `.gitattributes`
decides what a consumer receives.

We measured four widely-used published packages and 59% to 81% of their
shipped bytes are not functional package code: `integration_tests/`,
`.github/`, and in `fivetran/dbt_hubspot`'s case 5.9 MB of committed
`catalog.json` / `manifest.json` / `index.html`. None of the four ships a
`.gitattributes`. This is an unsolved gap in ecosystem practice rather than a
convention we are breaking.

So `integration_tests/`, `.github/`, `docs/`, and the contributor-facing
markdown are `export-ignore`d. `dbt_project.yml`, `packages.yml`, the
configured resource paths, `LICENSE`, `README.md`, and `CHANGELOG.md` ship.
Doing this before any models exist was deliberate: the install surface is much
harder to shrink once consumers depend on it.

**The tradeoff we are accepting:** someone who clicks "Download source" on a
GitHub release, or fetches the codeload tarball by hand, gets a package with no
tests in it. That is the same artifact dbt installs, so it is the correct thing
for it to contain, but it will surprise anyone who expects a source archive to
be the source. Cloning and forking are unaffected and still deliver everything.

A second, smaller cost: a `git:` install clones rather than downloading the
archive, so it ignores `export-ignore` entirely and delivers the full
repository. Hub installs are the majority and are what the README recommends,
so we accept the inconsistency rather than duplicating the exclusion list into
a mechanism that would also apply to clones.

**Revisit if:** GitHub changes the source-tarball endpoint to stop honouring
`export-ignore`, or dbt starts installing hub packages by clone. Either would
silently un-do this, so `docs/INSTALL_FOOTPRINT.md` records how to re-test it.

---

## The corporate hierarchy is a DAG, so `company_id` is not its grain

Written after a `unique` test on `snoco__company_hierarchy.company_id` failed
against real data with 30 duplicates. The model was built on the assumption that
a company has one position in one tree. It does not: **21 of the 394 companies
that have a parent have more than one.**

So the grain is one row per root-to-company path, keyed on a hash of
`hierarchy_path`, which is the only column that distinguishes the two rows a
multi-parent company produces. `parent_count` and `has_multiple_parents` are
exposed so the affected rows are findable rather than discovered later as a
fan-out in someone's join.

Considered and rejected: picking one parent to force uniqueness. There is no
field in the source that ranks parents, so any choice would be arbitrary and
would silently discard a real relationship. Returning both and labelling them is
honest; a consumer who needs one row per company can pick a rule that suits
their purpose, and now has the information to do it.

**Revisit if:** the provider adds a primary-parent indicator.

---

## `candidate_rank` counts companies, not rows

Also written after testing. The first version ranked candidate *rows*, and the
same company matching by both domain and name therefore occupied ranks 1 and 2.
Two consequences, the second one bad:

- Corroboration consumed two of the `snoco__match_max_candidates` slots, pushing
  genuine alternatives out of the list.
- `snoco__company_match` compared the winner to "rank 2" to decide ambiguity, so
  it compared the winner to **itself** and flagged every domain-and-name
  agreement as ambiguous. That is exactly backwards: agreement across two
  independent methods is the strongest evidence the package can produce, and it
  was being reported as the least trustworthy.

`candidate_rank` now ranks distinct companies, so rank 2 is always a different
company and the ambiguity comparison means what it says. The evidence-level
grain is unchanged: one row per input, company and method, so both pieces of
evidence remain visible.

**Revisit if:** a third match method is added, which would make the
per-company collapse rule worth stating explicitly rather than by score.

---

## A name that is only a legal form normalises to NULL

`normalize_company_name` strips trailing legal-form words with a pattern
requiring a preceding space, which means a name consisting of nothing else
survives it. A CRM record called `Inc.` normalised to `inc`, and measurement
found five distinct companies in the spine that also reduce to `inc`. The fuzzy
scorer rated all five 1.0, because they are identical strings.

A name carrying no information beyond its legal form cannot identify anybody, so
the last pass anchors on the whole string and empties it, `nullif` turns that
into NULL, and the matching models skip NULL names. 189 of 2,918,929 companies
normalise away entirely under this rule.

The alternative, a minimum-length guard on the normalised name, was rejected
because it is a threshold with no principle behind it and would discard real
short names like `BP` or `3M`.

**Revisit if:** the suffix list grows enough that legitimate names start
vanishing. The count above is the thing to watch.

---

## Layout follows the Fivetran shape: marts at the root of `models/`

Reviewed `fivetran/dbt_google_ads` v1.4.0, which is as close to a reference
implementation as the ecosystem has. Its layout is `models/<mart>.sql` at the
root, with `models/staging/`, `models/staging/tmp/` and `models/intermediate/`
beneath. We had marts in `models/companies/` and `models/matching/`.

Adopted the flat-marts layout. The rule it encodes is worth having: **anything
at the root of `models/` is a model this package publishes and a consumer may
reference; everything in a subdirectory is plumbing.** Grouping marts by theme
looked tidier and told a reader nothing they could act on. Nothing was lost in
the move, because the matching models were already gated by `config(enabled=)`
rather than by a directory-level config.

`int_snoco__match_input` moved from `models/matching/` to
`models/intermediate/`, where it always belonged. It is ephemeral and it is a
staging step for the matching models, not something a consumer selects.

**Not adopted: `models/staging/tmp/`.** Fivetran's tmp layer exists to give
`fill_staging_columns` a relation whose columns it can introspect, and to union
several connector schemas into one staging model. We do neither. There is one
share, every consumer reads the same objects, and ground rule 7 rejects the
schema-drift shim outright. A tmp layer here would be indirection with nothing
on the other end.

**Not adopted: materialising staging as tables.** Fivetran does, and is right
to: their staging unpacks, casts and back-fills missing columns, so it is real
work worth persisting once. Ours is a rename and a cast over a source that is
already a table, so a second copy of 16M rows would earn nothing.

**Revisit if:** the package ever reads more than one source layout, which is
the condition that makes a tmp layer pay for itself.

---

## Source relations are vars, one per object

Also taken from the Fivetran packages. Every source object gets a var whose
default is the `source()` call:

```yaml
snoco_company_index: "{{ source('snoco', 'company_index') }}"
```

Models read `{{ var('snoco_company_index') }}` rather than `source()` directly.
A consumer, or the integration test project, can then repoint any single table
at any relation without touching package code. That is the mechanism that lets
integration tests run against synthetic seeds, which ground rule 8 requires and
which was an open gap.

Chosen over passing table identifiers, which was the original plan and is
weaker: an identifier cannot express a table in a different database, a view, or
a seed, and all three are things a test or a consumer legitimately wants.

Verified rather than assumed, because it looks like it should break lineage:
the `source()` call is rendered in the consuming model's context, so dbt still
records `source.snowflake_company_data.snoco.<table>` in the model's
`depends_on`. Checked the manifest; the DAG is identical to a direct `source()`
reference. Source freshness and `--select source:snoco+` keep working.

The `identifier:` overrides that previously sat on each source table were
removed in the same change. They did the same job less well, and two mechanisms
for one thing is worse than either.

---

## The dbt floor is a tested claim, not a preference

`require-dbt-version` was `[">=1.10.0", "<3.0.0"]` from the scaffold onward, and
an earlier audit passed it because the *syntax* is valid. That was the wrong
check. The package's generic tests nest arguments under `arguments:`, which dbt
only accepts once `require_generic_test_arguments_property` defaults true, and
that happened in 1.10.8. Measured: 1.10.7 fails to parse with

```
macro 'dbt_macro__test_relationships' takes no keyword argument 'arguments'
```

and 1.10.8 is clean. The old floor advertised support for eight patch releases
the package does not work on, and the failure a consumer got was a macro error
naming an internal dbt macro rather than anything about versions.

Raised to `>=1.10.8`. dbt now rejects 1.10.7 with "This version of dbt is not
supported with the 'snowflake_company_data' package", which is the message
someone can act on.

**The general lesson, worth more than the fix:** a version bound is a claim
about behaviour. Checking that it parses tests the string, not the claim. Any
future change to either bound needs a run on the boundary versions.

**Revisit if:** the package stops using `arguments:`, which would lower the real
floor back to whatever the next-oldest constraint is.

---

## Domain normalisation lowercases first, and lives in one macro

Snowflake's `REGEXP_REPLACE` is case-sensitive by default. The domain
normalisation applied `lower()` around the outside of the scheme and `www.`
strips, so `WWW.Acme.com` became `www.acme.com` rather than `acme.com` and then
matched nothing on the deterministic domain join.

Silent in the worst way: the value looks normalised, the model builds, the tests
pass, and matching just quietly under-returns. CRM exports are full of
capitalised hostnames, so this was the common case rather than an edge case.

The logic was also duplicated between `stg_snoco__company_domains` and
`int_snoco__match_input`, and was wrong in both. It is now the
`normalize_domain` macro, which is the actual fix: one place to be right.

**Revisit if:** never. Extract the shared thing the first time you copy it.

---

## Reference deduplication picks one row, never one value per column

`snoco__company_securities` collapsed multiple reference rows per security with
`max()` on each column independently. Every value it returned was real and the
combination was not: the name from one row, the asset class from another, the
ticker from a third.

Measured on the current share: 10,278 identifier keys appear in more than one
reference row and 10,068 of those disagree on at least one attribute. Comparing
the two implementations directly, independent `max()` produced 112 rows matching
no real reference row at all; `row_number()`/`qualify` produces zero.

The ordering prefers the most completely populated row, then breaks ties on the
values so the result is stable across runs.

**The general rule:** aggregating columns independently to force a grain
fabricates rows whenever the source disagrees. If the answer is "one of these
rows", say that with `row_number()`, not with per-column aggregates.

---

## A test that always fires is not a test

`assert_snoco__lei_arrays_within_guard` warned whenever any company had an
oversized LEI array. The share always has about 230, so it warned on every build
in every consumer's project, for a provider defect nobody can fix. Anyone
running `--warn-error` got a hard failure on install.

Replaced with a drift check: `snoco__expected_oversized_lei_arrays` (230) and
`snoco__oversized_lei_array_tolerance` (50). Silent while the count sits where
we measured it, speaks up if the provider fixes the bug or makes it worse, which
are the only two states worth a human's attention. Setting the baseline to 0
restores "warn if any exist" for anyone who wants it.

Still `warn` rather than `error`: it is provider data we do not control, and
drift is a reason to look, not a reason to break someone's build.

---

## No `fill_staging_columns` / schema-drift shim

Fivetran's staging pattern emits `cast(null as <type>) as <column>` when an expected column is missing, so downstream models always compile. That trade makes sense for them: a hard failure across thousands of tenants with per-tenant schema variance is worse than a silently null column.

It does not make sense here. Every consumer of this package reads the *same* share, so a provider schema change breaks everyone identically and simultaneously. We want to find out on the next run, not discover it months later as an all-null column that quietly corrupted a mart.

**Revisit if:** the package ever reads a source with genuine per-consumer schema variance.

---

## Every resource carries a `+schema`, and that is load-bearing

`dbt_project.yml` sets `+schema` at the package root and again on `staging/`.
The root key looks redundant, because `<target_schema>_snowflake_company_data`
is close to what a consumer would get anyway. It is not redundant, and the
reason is invisible from inside this repo.

dbt passes the configured schema to `generate_schema_name` as
`custom_schema_name`. Plenty of real projects override that macro, and a common
override shape branches on `custom_schema_name is none` and falls back to
deriving a schema from the node's path or file name. That is correct for the
project's own models and nonsense for a package's: the node is
`models/staging/stg_snoco__company_index.sql`, so the fallback returns the
staging model's own file name as a schema name.

Observed, not theorised. An install into a project whose `generate_schema_name`
infers schemas from folder structure would have produced a schema derived from
`stg_snoco__company_index.sql`. It did not, because `+schema` was set and the
override took its normal branch.

So the invariant is: **every resource this package publishes must resolve to a
non-null custom schema name.** The root key satisfies it for everything today,
since configs inherit down the path. A new subdirectory is fine. A new resource
type declared outside `models:`, seeds most likely, is not, and would need its
own key.

Measured rather than asserted. Parsing `integration_tests/` on dbt-core 1.12.0
and reading `config.schema` off every node in the manifest whose `package_name`
is `snowflake_company_data`:

```
package nodes: 85
  resource_type=model  custom_schema_name='snowflake_company_data'
  resource_type=model  custom_schema_name='stg_snowflake_company_data'
  resource_type=test   custom_schema_name='dbt_test__audit'
nodes with NULL custom schema name: 0
```

Note the tests are covered by dbt-core's own default rather than by anything
here, so the two model values are the ones this repo is responsible for. Re-run
that check after adding a resource type.

The staging `+schema` is a different thing and is only a preference: it keeps
nine views out of the mart schema.

Documented in three places on purpose, because the failure mode is silent and
appears only in someone else's project: a comment at the config block where
someone would delete it, a note in the README for the consumer who overrides the
macro, and a trap entry in CLAUDE.md for whoever edits this next.

**Revisit if:** never, really. The cost is two lines and the failure it prevents
is one nobody would debug quickly.

---

## The replica install is documented as a first-class shape

The README used to mention reading a replica in a four-line aside under a
configuration table. It is now a section with the rationale, the SQL, and the
guard advice.

Reading the share directly is the shape that gets someone started. Reading a
copy is the shape they end up at, and it is the only reason `snoco_schema` is a
variable rather than a constant, so burying it undersold both the option and the
configuration surface built for it.

Three concrete things the share cannot give: `ROW_COUNT` and `BYTES` are `NULL`
on every secure view, so no size signal; no object carries a load timestamp, so
no freshness anchor; and the provider republishes on their own schedule, so a
long build can read two versions of the spine.

The section says `CREATE TABLE ... AS SELECT` rather than `CLONE`, because
Snowflake does not support cloning out of a listing-derived database and these
are views regardless. It says to add `cloned_at` in the copy, which is what makes
the source freshness block in the next section usable rather than hypothetical.
It says to guard the copy on a row count, because `CREATE OR REPLACE` on a
truncated pull silently replaces good data. And it says to keep the replica in
one schema, preserving the two-var isomorphism with the share, while noting the
per-object relation vars for anyone who cannot.

No replication script ships. It would be one warehouse's opinion about
scheduling, roles and guard thresholds, and every consumer's answer differs.

**Revisit if:** enough people build the same replication procedure that shipping
a macro to generate it beats describing it.

---

## The README documents the git install, not the hub install, until listed

The README told consumers to pin `zelloptt/snowflake_company_data` with a
version range. That is dbt Package Hub syntax, and it resolves against
`hub.getdbt.com`. Checked, both ends: `hub.getdbt.com/api/v1/zelloptt/
snowflake_company_data.json` returns 404, and `zelloptt` does not appear in
hubcap's `hub.json`. The snippet fails for everyone who copies it, with a
package-not-found error rather than a version error.

Worth being precise about, because the obvious diagnosis is wrong. The missing
release tag is a real defect and is fixed separately, but a tag does not repair
this snippet. Hub resolution needs a hub listing. The tag repairs a *git*
install, which is a different block of YAML.

So the README now leads with the git install and keeps the hub block as the
form to switch to once listed. The git install is honestly worse: a clone
ignores `export-ignore`, so the consumer receives `integration_tests/`,
`.github/` and our contributor docs along with the 38 files that are the
package. Nothing is parsed, since dbt reads only the declared paths, so it is
disk rather than behaviour. Said plainly in the README instead of hidden,
because the alternative right now is an install that does not work at all.

**Revisit when:** the hubcap PR lands and the listing exists. At that point the
two blocks swap places and the git install becomes the footnote.

---

## Audited against hubcap's package best practices

Every requirement in
[`package-best-practices.md`](https://github.com/dbt-labs/hubcap/blob/main/package-best-practices.md)
was checked against the repo rather than against memory of it. The result table
lives in `RELEASE.md`, next to the submission runbook where it will actually be
re-read. Recorded here is what changed and what was decided.

**One real gap, fixed.** Four casts used literal `boolean` and `float` where dbt
Core has `type_boolean()` and `type_float()`. Both exist at the `>=1.10.8` floor,
confirmed by listing the type macros in dbt-core 1.10.8 itself, and both render
byte-identically on Snowflake (`SnowflakeColumn.translate_type` returns `float`
and `boolean` unchanged), so the change is convention with no behavioural risk.
The three `cast(... as date)` casts in staging stay literal: dbt Core has no
`type_date`.

**One rule in `CLAUDE.md` was wrong and is corrected.** Ground rule 2 said
"never hard-code a database or schema name, hubcap makes this a MUST". hubcap's
MUST is narrower and is about *table references*: use `ref` or `source`. For
database and schema it says only SHOULD NOT *assume*, which an overridable var
satisfies whether or not it carries a default.

The distinction is not academic. Read the old wording literally and you would
delete the `MARKETPLACE_CYBERSYN` and `PUBLIC_DATA_FREE` defaults to comply with
a MUST that does not exist, undoing `af28dee` and returning the package to
requiring configuration before it works at all.

**One deliberate deviation from a SHOULD.** hubcap recommends dbt Core's
cross-database macros. Type macros are used everywhere they apply. Function
macros, `dbt.concat()`, `dbt.length()`, `dbt.split_part()`, are not: this package
is Snowflake-only because its data source is a Snowflake Marketplace share, so a
portable wrapper around a function that will only ever compile for one adapter
is indirection with nothing behind it. That is ground rule 9, and RFC 2119 SHOULD
allows a deviation that has been weighed. Written down so the next reviewer sees
a decision rather than an oversight.

**One open question, not ours to settle here.** hubcap notes that
production-ready packages should be at 1.0.0 or above. This package is 0.1.0 and
says so. Both are honest and they conflict only at submission, so `RELEASE.md`
states the choice rather than pretending it does not exist.

Everything else already passed, including the two MUSTs most likely to fail
silently: no hard-coded table reference anywhere (every `from` and `join` target
is a CTE, a `ref()`, or a var defaulting to `source()`), and nothing that
overrides dbt Core behaviour for resources this package did not create (five
distinctly named macros, none a dbt hook; vars and configs namespaced; all 13
doc blocks `snoco_`-prefixed, which matters because doc block names are global).

---

## Country and state are EDGAR codes; ISO comes from the geography index

`snoco__companies` used to publish `country` and `state` as the coalesced SEC
and EAV values. Those columns are EDGAR state-or-country codes, not ISO and
not a country name: `X1` is the United States (617,791 rows), `E9` Cayman,
`Z4` Canada. They also carry 12,048 empty strings, 1,034 `XX`/`xx`
placeholders, and a handful of ISO codes and one USPS state (`FL`) in the
country column. `STATE` mixes USPS (`TX`) with EDGAR (`A8` Quebec) and 14,340
empty strings.

Two things made this worse than an undocumented vocabulary.

Empty strings are truthy to `coalesce`, so a blank SEC country masked a real
EAV one, and `where country is not null` returned the blanks. Domains and
identifiers already filtered `!= ''`; this column did not. And the trustworthy
values were already in the model: `country_iso_alpha2` / `alpha3`, populated
on 681,787 rows via `country_geo_id` → `geography_index`, including rows
whose EDGAR code is blank or `XX`. `state_geo_id` was staged and then dropped.

So the mart now:

- Filters on the ISO columns, and joins `state_geo_id` the same way as
  `country_geo_id`, exposing `state_iso_3166_2`, `country_name`, `state_name`.
- Keeps the source codes as `edgar_country_code` / `edgar_state_code`, after
  turning `''` and `XX` into NULL *on each source before coalesce*, so a blank
  SEC value can fall through to EAV.
- Drops `country` and `state` as column names, because keeping them would
  invite `where country = 'US'` against a column whose United States is `X1`.
- Names the EDGAR codes from a shipped copy of the SEC list
  (`snoco__edgar_state_country_codes` → `edgar_country_name` /
  `edgar_state_name`). Ground rule 8 forbids copying the *share* into git. It
  does not forbid a US government classification table; that is the same
  exception SIC already had, and it is the thing that makes `X1` readable.
  The list is a model, not a seed: `dbt run` has to materialize it, and it
  disables with `snoco_company_enabled` the same way the company marts do.

Considered and rejected: shipping an EDGAR → ISO seed. The geography index
already is that mapping, it is what the share gives us, and inventing one
would also pretend the 69 leaked ISO values are cleaner than they are. The
name lookup is a different job and is the one the SEC list actually does.

**Revisit if:** the provider starts writing ISO in `COUNTRY`, at which point
`edgar_country_code` becomes a misnomer and the ISO join is the thing to
re-check. Or if the SEC republishes the list, at which point the model needs
a refresh from the same URL.

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

## Source location defaults to the maintainers' replica, not to a guess

Superseded the original decision, which defaulted `snoco_database` to
`SNOWFLAKE_PUBLIC_DATA_FREE` on the reasoning that it is the name Snowflake's
own examples use.

That reasoning does not survive contact with the install step. The database name
is chosen by whoever runs `CREATE DATABASE ... FROM LISTING`, so it is different
in every account and **there is no default that works unconfigured.** The
question is therefore not which default is correct, it is which failure is most
useful, and a plausible-looking default is the worst of the options: it is
indistinguishable from a permissions problem, and a consumer who has genuinely
named their database `SNOWFLAKE_PUBLIC_DATA_FREE` gets a package that half-works
against a schema layout nobody verified.

So the defaults describe the deployment we actually run and test against:
`MARKETPLACE_CYBERSYN.PUBLIC_DATA_FREE`, a daily replica of the ten objects
this package reads. An unconfigured external install fails immediately, naming a
database the consumer has never heard of, which reads unambiguously as "you did
not set this" rather than as a grant problem. The README says so directly.

Not `target.database` either, which is Fivetran's default and right for them
because Fivetran lands data in the user's own database. Ours is a separate
database whichever layout you use.

Related, and unchanged: `snoco_database` is deliberately not declared in the
package's `vars:` block. dbt resolves `var('x', default)` to null rather than the
default when the package declares `x: null`, because the var is then defined.
Verified still true on dbt-core 1.12.0.

**Revisit if:** Snowflake standardizes the database name at install time, which
would make a real default possible for the first time.

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

## No `fill_staging_columns` / schema-drift shim

Fivetran's staging pattern emits `cast(null as <type>) as <column>` when an expected column is missing, so downstream models always compile. That trade makes sense for them: a hard failure across thousands of tenants with per-tenant schema variance is worse than a silently null column.

It does not make sense here. Every consumer of this package reads the *same* share, so a provider schema change breaks everyone identically and simultaneously. We want to find out on the next run, not discover it months later as an all-null column that quietly corrupted a mart.

**Revisit if:** the package ever reads a source with genuine per-consumer schema variance.

# Discovery

Live introspection of the Snowflake Public Data (Free) share. **This file is the
source of truth for column names and shapes.** Public documentation for this
dataset is thin and in places wrong; everything below was measured, not read.

Scanned 2026-08-08 against Marketplace listing `GZTSZ290BV255`, schema
`PUBLIC_DATA_FREE`.

The listing suggests the database name `MARKETPLACE_CYBERSYN` at acquisition,
but any consumer may choose another, which is why every source location in this
package is a var.

**The listing also exposes a `CYBERSYN` schema, and it is not interchangeable.**
It is the older Financial Data Package layout and holds 6 of the 9 objects
below: `COMPANY_CHARACTERISTICS`, `COMPANY_DOMAIN_RELATIONSHIPS` and
`SEC_CIK_INDEX` are absent from it. Everything here was measured against
`PUBLIC_DATA_FREE`.

---

## Objects modelled

Nine of the ~370 objects in the share. Everything else is out of scope.

| Object | Rows | Grain (verified) |
|---|---:|---|
| `COMPANY_INDEX` | 2,918,929 | `company_id`, **unique** |
| `COMPANY_CHARACTERISTICS` | 11,745,288 | `company_id` + `relationship_type`, **not unique** (see trap 2) |
| `COMPANY_DOMAIN_RELATIONSHIPS` | 319,269 | `company_id` + `domain_id`, unique |
| `COMPANY_RELATIONSHIPS` | 848 | `company_id` + `related_company_id` + `relationship_type` |
| `COMPANY_SECURITY_RELATIONSHIPS` | 985,971 | `company_id` + `security_id_type` + `security_id`, unique |
| `SEC_CIK_INDEX` | 981,128 | **`cik`**, unique. *Not* `company_id` (see trap 3) |
| `OPENFIGI_SECURITY_INDEX` | 119,273 | `top_level_openfigi_id` |
| `PERMID_SECURITY_INDEX` | 25,751 | `permid_security_id` |
| `GEOGRAPHY_INDEX` | 573,277 | `geo_id`, unique |

All of them are **secure views**, not tables. `INFORMATION_SCHEMA.TABLES.ROW_COUNT`
and `BYTES` are `NULL` for every one of them, confirming the trap already
recorded in `CLAUDE.md`. Every count above is a real `count(*)`.

## Column reference

Only the columns the package actually reads. Types are Snowflake types as
reported by `INFORMATION_SCHEMA.COLUMNS`. **Every column is nullable.**

### `COMPANY_INDEX`
| Column | Type | Notes |
|---|---|---|
| `COMPANY_ID` | TEXT | 24-char opaque hash. The spine key. |
| `COMPANY_NAME` | TEXT | |
| `ENTITY_LEVEL` | TEXT | **Constant `'Corporate'`** for all 2,918,929 rows. Carries no information; not surfaced. |
| `EIN` | TEXT | populated on 306,666 (10.5%) |
| `CIK` | TEXT | populated on 697,780 (23.9%) |
| `LEI` | **ARRAY** | populated on 63,978 of 2,934,685 (2.2%), every array exactly one element (measured 2026-11-11; was 59,163, with arrays up to 5,287). See trap 1. |
| `PERMID_COMPANY_ID` | TEXT | populated on 2,826,707 (96.8%) |
| `PRIMARY_TICKER` | TEXT | populated on 19,565 (0.7%) |
| `PRIMARY_EXCHANGE_CODE` / `_NAME` | TEXT | |
| `GLOBAL_TICKERS` | **ARRAY** | **100% NULL across all 2.9M rows.** See trap 4. |

### `COMPANY_CHARACTERISTICS` (entity-attribute-value)
`COMPANY_ID`, `COMPANY_NAME`, `RELATIONSHIP_TYPE`, `VALUE`,
`RELATIONSHIP_START_DATE`, `RELATIONSHIP_END_DATE` (all TEXT except the dates).

The 15 `RELATIONSHIP_TYPE` values, with row counts. This list is the whole
attribute vocabulary; there is nothing else in the column:

| `relationship_type` | Rows | Coverage of spine |
|---|---:|---:|
| `company_name` | 2,918,930 | 100.0% |
| `permid_company_id` | 2,826,708 | 96.8% |
| `cik` | 697,781 | 23.9% |
| `company_legal_structure` | 693,289 | 23.8% |
| `business_address_country` | 691,569 | 23.7% |
| `business_address_state` | 688,696 | 23.6% |
| `business_address_line1` | 684,217 | 23.4% |
| `business_address_city` | 683,981 | 23.4% |
| `business_address_zip` | 680,205 | 23.3% |
| `business_address_line2` | 336,662 | 11.5% |
| `lei` | 63,978 | 2.2% (measured 2026-11-11; was 333,143 while trap 1 was live) |
| `ein` | 306,666 | 10.5% |
| `sec_industry_group` | 126,029 | 4.3% |
| `sic_description` | 38,706 | 1.3% |
| `sic_code` | 38,706 | 1.3% |

### `SEC_CIK_INDEX`
32 columns. The package reads `COMPANY_ID`, `CIK`, `COMPANY_NAME`, `EIN`,
`SIC`, `SIC_CODE_CATEGORY`, `SIC_CODE_DESCRIPTION`, `SEC_FILER_CATEGORY`,
`INCORPORATION_STATE`, `INCORPORATION_COUNTRY`, `ADDRESS_LINE_1`,
`ADDRESS_LINE_2`, `CITY`, `STATE`, `ZIP`, `COUNTRY`, `COUNTRY_GEO_ID`,
`STATE_GEO_ID`, `PHONE_NUMBER`.

Note the SIC column is named **`SIC`**, not `SIC_CODE`. `SIC_CODE` does not
exist on this object; `COMPANY_CHARACTERISTICS` uses `sic_code` as a
*relationship_type value*. Easy to conflate; they are different things.

`COUNTRY` and `STATE` are EDGAR state-or-country codes, not ISO. See trap 8.
`COUNTRY_GEO_ID` / `STATE_GEO_ID` join to `GEOGRAPHY_INDEX` and are the
trustworthy path to ISO codes.

### Others
- `COMPANY_DOMAIN_RELATIONSHIPS`: `COMPANY_ID`, `COMPANY_NAME`, `DOMAIN_ID`, `RELATIONSHIP_START_DATE`, `RELATIONSHIP_END_DATE`
- `COMPANY_RELATIONSHIPS`: adds `RELATED_COMPANY_ID`, `RELATED_COMPANY_NAME`, `RELATED_ENTITY_LEVEL`, `RELATIONSHIP_TYPE`
- `COMPANY_SECURITY_RELATIONSHIPS`: `COMPANY_ID`, `COMPANY_NAME`, `SECURITY_ID_TYPE`, `SECURITY_ID`, `SECURITY_NAME`
- `GEOGRAPHY_INDEX`: `GEO_ID`, `GEO_NAME`, `LEVEL`, `ISO_NAME`, `ISO_ALPHA2`, `ISO_ALPHA3`, `ISO_NUMERIC_CODE`, `ISO_3166_2_CODE`

---

## Traps

### Trap 1: unrelated companies share one identical 5,287-element `LEI` array (fixed by the provider, 2026-11)

**Status: fixed upstream as of 2026-11.** Re-measured 2026-11-11 with aggregate
queries against `PUBLIC_DATA_FREE.COMPANY_INDEX` on the share:

| | Now (2026-11-11) | When found |
|---|---:|---:|
| rows in `COMPANY_INDEX` | 2,934,685 | 2,918,929 |
| non-null `LEI` | 63,978 | 59,163 |
| more than one element | 0 | 1,913 |
| more than 25 elements | 0 | 230 |
| largest array | 1 | 5,287 |
| `LATERAL FLATTEN(lei)` rows, unguarded | 63,978 | 333,143 |
| `LATERAL FLATTEN(lei)` rows, guarded | 63,978 | 63,142 |

A replica cloned the same day matched in shape: 2,933,483 rows, 63,556 with an
LEI, 0 oversized, largest array 1. The guard now withholds nothing and the
unguarded and guarded flattens are identical.

`snoco__max_identifier_array_size` stays at 25 as a safety net, since it costs
nothing while every array is size 1. `snoco__expected_oversized_lei_arrays` is
now 0, so the guard test warns only if oversized arrays return. See
`DECISIONLOG.md`.

**What the fix does not change.** A single LEI can still sit on more than one
company: 1,312 of 62,614 distinct LEIs belong to 2 to 4 companies (2,676
companies in all, 1,263 of those LEIs on exactly two). That is a different
shape from the shared arrays below, it is not something the array cap can see,
and a lookup by LEI should still expect the occasional duplicate.

The rest of this section is the defect as it was found, kept for history.

`COMPANY_INDEX.LEI` is an ARRAY. Measured when the trap was found:

| | Companies |
|---|---:|
| non-null `LEI` | 59,163 |
| more than one element | 1,913 |
| more than 25 elements | 230 |
| of those, with a `/` in the name | 224 (97%) |

The largest array holds **5,287** elements, and **47 different companies carry
the byte-identical array**. That holds at every size: grouping the over-guard
rows by array size gives exactly one distinct array value per size, shared
across all the companies at that size.

```
array_size   companies   distinct array values
     5,287          47                       1
       816           9                       1
       115          43                       1
```

Identical identifier sets across unrelated legal entities is not a real
ownership pattern. Combined with the slash concentration, this reads as an
upstream grouping bug where a slash collapses a partition key. It is not
documented anywhere.

**Consequence, and it is about correctness rather than volume:** a naive
`LATERAL FLATTEN(lei)` produces 333,143 rows where the guarded version produces
63,142. The extra **270,001 rows are false company-to-LEI assertions**, so a
lookup by LEI returns 47 companies for a single identifier that belongs to at
most one. The row-count inflation is real but modest (it would grow the whole
identifier table by about 7%); the damage is that the rows are wrong, not that
there are many of them.

`snoco__max_identifier_array_size` (default 25) drops these before the flatten.
A warn-severity test compares the affected count with
`snoco__expected_oversized_lei_arrays` and warns on drift; that baseline was 230
until the provider fix and is 0 from 0.1.1.

### Trap 2: `RELATIONSHIP_END_DATE` is always NULL, so there is no SCD close-out

`COMPANY_CHARACTERISTICS.RELATIONSHIP_END_DATE` is NULL on **all 11,745,288
rows**. There are zero closed records. Filtering `where relationship_end_date
is null` to get "current" values is a no-op that reads as if it did something.

The table is nevertheless not unique on `(company_id, relationship_type)`:
11,745,288 rows against 11,471,303 distinct pairs. There are **no exact
duplicate rows**. The excess comes from 1,918 company/type pairs that carry
more than one distinct `value`, and 1,913 of those are `lei` (same upstream
bug as trap 1). Every other attribute type has at most one such pair.

**Consequence:** the pivot to one row per company must deduplicate explicitly.
The package picks a deterministic winner by `row_number()` ordered by
`relationship_start_date desc, value`, rather than assuming uniqueness or
using `min`/`max`, so the choice is stable across runs.

### Trap 3: `SEC_CIK_INDEX` is keyed on `CIK`, and 28.7% of it has no company

981,128 rows, but only 699,305 distinct non-null `company_id`. The remaining
**281,823 rows have a NULL `company_id`** and cannot be joined to the spine at
all. `count(distinct cik)` is 981,128, exactly the row count, so **`CIK` is the
unique key**.

**Consequence:** joining `SEC_CIK_INDEX` on `company_id` silently drops 28.7%
of SEC filers. The staging model keys on `cik` and preserves the unresolved
rows; only the company-level mart inner-joins to the spine.

### Trap 4: `GLOBAL_TICKERS` exists but is entirely empty

`COMPANY_INDEX.GLOBAL_TICKERS` is declared ARRAY and is NULL on every one of
the 2,918,929 rows. `PRIMARY_TICKER` is populated on 19,565.

**Consequence:** any model built on `GLOBAL_TICKERS` compiles, runs, and
returns nothing. Per `CLAUDE.md` ground rule 3 the column is not modelled.
`OPENFIGI_SECURITY_INDEX.GLOBAL_TICKERS` is a different column and is
populated; do not confuse them.

### Trap 5: the corporate hierarchy is 848 rows

`COMPANY_RELATIONSHIPS` contains 424 `Parent` edges and 424 `Subsidiary` edges,
which are the same 424 relationships stored in both directions. Against a
2.9M-company spine that is a coverage of roughly 0.015%.

**Consequence:** the hierarchy model is real but nearly empty, and
`snoco__hierarchy_max_depth` will never be approached in practice. The README
must not oversell it. Recursion still needs a depth guard because nothing in
the data prevents a cycle.

### Trap 5a: the hierarchy is a DAG, not a tree

Found by testing, not by reading. **21 of the 394 companies that have a parent
have more than one.** The 424 edges therefore do not form a forest of trees, and
walking them produces 713 rows covering 683 distinct companies.

**Consequence:** `company_id` is not unique in any model built by walking these
edges, and a `unique` test on it fails against real data. The grain is one row
per root-to-company path. `snoco__company_hierarchy` keys on a hash of the path
and exposes `parent_count` / `has_multiple_parents` so the multi-parent rows can
be found and resolved deliberately rather than discovered by a fan-out
downstream.

Observed maximum depth is 2, against a `snoco__hierarchy_max_depth` of 10.

### Trap 6: company to security is a type-qualified join, not a foreign key

`COMPANY_SECURITY_RELATIONSHIPS.SECURITY_ID` is a single TEXT value whose
meaning depends on `SECURITY_ID_TYPE`:

| `security_id_type` | Rows | Resolves against |
|---|---:|---|
| `openfigi_figi_id` | 815,921 | `OPENFIGI_SECURITY_INDEX.OPENFIGI_FIGI_ID` (ARRAY) |
| `openfigi_composite_id` | 99,766 | `OPENFIGI_SECURITY_INDEX.OPENFIGI_COMPOSITE_ID` (ARRAY) |
| `permid_quote_id` | 41,654 | `PERMID_SECURITY_INDEX.PERMID_QUOTE_ID` (ARRAY) |
| `permid_security_id` | 19,852 | `PERMID_SECURITY_INDEX.PERMID_SECURITY_ID` (TEXT) |
| `openfigi_share_class_id` | 8,778 | `OPENFIGI_SECURITY_INDEX.OPENFIGI_SHARE_CLASS_ID` (ARRAY) |

Four of the five target columns are ARRAYs, so the join is
`ARRAY_CONTAINS(security_id::variant, <array_column>)` rather than equality.
dbt's built-in `relationships` test cannot express this, which is why the
package ships a singular test instead.

### Trap 7: `DOMAIN_ID` is clean, but not unique

319,269 rows, 289,774 distinct domains, 315,950 distinct companies. Domains are
already normalised (no scheme, no `www.`, no path); only **65 rows** contain a
`/`, `http`, or leading `www.`.

**Consequence:** domain is an excellent deterministic match key but it is
many-to-many. Matching on it must pick a winner rather than assume one row.

### Trap 8: `COUNTRY` is EDGAR state-or-country codes, mixed, and full of empty strings

`SEC_CIK_INDEX.COUNTRY` is not a country name and it is not ISO 3166. It is the
SEC's [EDGAR state-or-country list](https://www.sec.gov/submit-filings/filer-support-resources/edgar-state-country-codes),
the same vocabulary used for `STATE`. Current codes (post-February 2010); a
[comparison to the pre-2010 list](https://www.sec.gov/edgar/searchedgar/edgarcompstate.htm)
exists because searches return whatever the filer used at the time.

Measured on the coalesced `country` column the mart used to publish:

| Value | Rows | Official EDGAR meaning | Notes |
|---|---:|---|---|
| `X1` | 617,791 | United States | Country-level US. Not `US`. |
| `E9` | 13,854 | Cayman Islands | |
| `Z4` | 11,049 | Canada (federal) | Provinces are `A0`–`A9`, `B0`. |
| `''` | 12,048 | *(not a code)* | Empty string, not NULL. |
| `XX` / `xx` | 1,034 | Unknown | Official placeholder. |
| `US` | 69 | *(not in the list)* | ISO alpha-2 leak. US is `X1`. |
| `CA` | 14 | California | Or ISO Canada. Canada is `Z4`. |
| `FR` | 1 | *(not in the current list)* | France is `I0`. Pre-2010 `FR` was "unknown state". |
| `FL` | 1 | Florida | A state code in the country column. |

`STATE` has the same shape: USPS codes (`TX`) alongside EDGAR codes (`A8`
Quebec, `E9` Cayman) and **14,340 empty strings**. That is the list working
as designed: it is one vocabulary for states *or* countries, so a Cayman
address can legally put `E9` in `STATE`.

Two modelling failures follow, and they compound.

`coalesce(sec.country, eav.country)` treats `''` as present, so a blank SEC
value masks a real attribute-table value. And `where country is not null`
returns those 12,048 blanks plus the 1,034 `XX` placeholders, because none of
them are NULL. Domains and identifiers already filter `!= ''`; this column did
not.

The ISO columns are the trustworthy ones. `country_iso_alpha2` /
`country_iso_alpha3` resolve through `COUNTRY_GEO_ID` → `GEOGRAPHY_INDEX` and
are populated on 681,787 rows, including rows whose EDGAR code is blank or
`XX`. `state_iso_3166_2` does the same from `STATE_GEO_ID`.

**Consequence:** do not filter on `country` or `state`. The mart exposes the
EDGAR values as `edgar_country_code` / `edgar_state_code` after turning empty
strings and `XX` into NULL, names them from the shipped SEC list
(`snoco__edgar_state_country_codes` → `edgar_country_name` /
`edgar_state_name`), and uses the ISO columns as the ones to filter on. No
EDGAR → ISO mapping is maintained in the package; the geography index already
is that mapping.

---

## What this share is not

Measured, so the README does not overpromise:

- **No employee count and no revenue.** Neither exists on any object in scope.
- **Industry coverage is thin.** `sic_code` on 1.3% of the spine,
  `sec_industry_group` on 4.3%.
- **Address coverage is ~23%**, concentrated in the SEC-filer population.
- **96.8% carry a PermID**, confirming the universe skews to the
  securities/regulatory world rather than general SMB firmographics.

## Reproducing this

```sql
-- object list and the null ROW_COUNT trap
select table_name, row_count, bytes, table_type
from <db>.information_schema.tables
where table_schema = 'PUBLIC_DATA_FREE' and table_name like 'COMPANY%';

-- the attribute vocabulary
select relationship_type, count(*)
from <db>.public_data_free.company_characteristics
group by 1 order by 2 desc;

-- trap 1 (expect 1 since the provider fix in 2026-11)
select max(array_size(lei)), count_if(array_size(lei) > 25)
from <db>.public_data_free.company_index;

-- trap 3
select count(*) filter (where company_id is null), count(distinct cik), count(*)
from <db>.public_data_free.sec_cik_index;

-- trap 8
select country, count(*)
from <db>.public_data_free.sec_cik_index
group by 1 order by 2 desc
limit 20;
```

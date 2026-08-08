{{ config(enabled = var('snoco_company_enabled', true)) }}

{% set max_array = var('snoco__max_identifier_array_size', 25) %}

-- One row per (company, identifier type, identifier value).
--
-- This is where the LEI fan-out guard lives, and it is the single most
-- important defensive line in the package.
--
-- COMPANY_INDEX.LEI is an ARRAY. 59,163 companies carry one, 1,913 carry more
-- than one, and 230 carry more than 25. Among those 230, the arrays are shared
-- verbatim: 47 different companies hold the identical 5,287-element array, and
-- the same one-array-many-companies pattern repeats at every large size. 224 of
-- the 230 have a slash in the name. It is a provider-side grouping bug.
--
-- The reason to cap is correctness rather than size, and it is worth being
-- honest about that. Unguarded this produces 333,143 LEI rows against 63,142
-- guarded, which would grow the identifier table by about 7% and would be
-- tolerable if the rows were right. They are not: a lookup by one of those LEIs
-- returns 47 companies, at most one of which owns it.
--
-- Arrays longer than snoco__max_identifier_array_size are excluded before the
-- flatten rather than after it, because filtering after still materialises the
-- explosion. Affected companies keep every other identifier; only their LEI
-- list is withheld, and the warn-severity test reports the count each run.

with spine as (

    select * from {{ ref('stg_snoco__company_index') }}

),

scalar_identifiers as (

    select company_id, 'ein'               as identifier_type, ein               as identifier_value
    from spine where ein is not null

    union all
    select company_id, 'cik',               cik
    from spine where cik is not null

    union all
    select company_id, 'permid_company_id', permid_company_id
    from spine where permid_company_id is not null

    union all
    select company_id, 'ticker',            primary_ticker
    from spine where primary_ticker is not null

),

-- Materialised as its own step so the size guard is applied BEFORE the
-- lateral flatten, not as a predicate over its output.
lei_within_guard as (

    select company_id, lei_array
    from spine
    where lei_array is not null
      and array_size(lei_array) between 1 and {{ max_array }}

),

lei_identifiers as (

    select
        g.company_id,
        'lei' as identifier_type,
        cast(f.value as {{ dbt.type_string() }}) as identifier_value
    from lei_within_guard as g,
         lateral flatten(input => g.lei_array) as f

)

select
    company_id,
    identifier_type,
    identifier_value
from scalar_identifiers
where identifier_value != ''

union all

select
    company_id,
    identifier_type,
    identifier_value
from lei_identifiers
where identifier_value is not null
  and identifier_value != ''

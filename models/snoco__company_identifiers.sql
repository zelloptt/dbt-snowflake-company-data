{{ config(enabled = var('snoco_company_enabled', true)) }}

-- Each record represents one external identifier held by one company.
--
-- Long rather than wide on purpose. A company can carry several LEIs, and
-- pivoting that to a single column forces an arbitrary choice; this shape lets
-- a consumer join on whichever identifier system they already have.
--
-- Grain: one row per company_id + identifier_type + identifier_value, enforced
-- by a unique test on identifier_sk.
--
-- Composite grain gets a surrogate key rather than a multi-column uniqueness
-- test, because dbt-core 1.10.6 broke the multi-argument test syntax that
-- dbt_utils.unique_combination_of_columns relies on.
--
-- LEI arrays longer than snoco__max_identifier_array_size are excluded upstream
-- to stop a provider-side bug fanning 1,913 companies into ten million rows.
-- See int_snoco__company_identifiers and docs/DISCOVERY.md trap 1.

with identifiers as (

    select distinct
        company_id,
        identifier_type,
        identifier_value
    from {{ ref('int_snoco__company_identifiers') }}

)

select
    {{ dbt.hash(
        "company_id || '|' || identifier_type || '|' || identifier_value"
    ) }} as identifier_sk,
    company_id,
    identifier_type,
    identifier_value
from identifiers

{{ config(enabled = var('snoco_securities_enabled', true) and var('snoco_company_enabled', true)) }}

-- Each record represents one security issued by one company, with the security
-- reference data resolved.
--
-- Grain: one row per company_id + security_id_type + security_id, enforced by a
-- unique test on company_security_sk.
--
-- The company-to-security join is the awkward part of this dataset.
-- security_id is a single column whose meaning depends on security_id_type, and
-- four of the five types resolve against ARRAY columns rather than scalars.
-- Written as a join predicate that is the obvious thing to write:
--
--     array_contains(cs.security_id::variant, ofi.figi_id_array)
--
-- it is 985,971 rows against 119,273 rows with no equality to hash on, which is
-- 117 billion array probes. So the reference arrays are flattened into a
-- (type, value) lookup first and joined by equality instead.
--
-- The flatten is safe here, unlike the LEI arrays on company_index. These are
-- genuinely multi-valued (one security really does carry a FIGI per exchange),
-- and they are bounded: the largest FIGI array holds 707 entries and the whole
-- lookup is about 2.6M rows. No guard is needed, and adding one would silently
-- drop real securities.

with company_securities as (

    select * from {{ ref('stg_snoco__company_securities') }}

),

openfigi as (

    select * from {{ ref('stg_snoco__openfigi_securities') }}

),

permid as (

    select * from {{ ref('stg_snoco__permid_securities') }}

),

security_lookup as (

    select
        'openfigi_figi_id'                      as security_id_type,
        cast(f.value as {{ dbt.type_string() }}) as security_id,
        openfigi.security_name,
        openfigi.asset_class,
        openfigi.primary_ticker,
        cast(null as {{ dbt.type_string() }})   as exchange_code
    from openfigi, lateral flatten(input => openfigi.figi_id_array) as f

    union all

    select
        'openfigi_composite_id',
        cast(f.value as {{ dbt.type_string() }}),
        openfigi.security_name,
        openfigi.asset_class,
        openfigi.primary_ticker,
        cast(null as {{ dbt.type_string() }})
    from openfigi, lateral flatten(input => openfigi.composite_id_array) as f

    union all

    select
        'openfigi_share_class_id',
        cast(f.value as {{ dbt.type_string() }}),
        openfigi.security_name,
        openfigi.asset_class,
        openfigi.primary_ticker,
        cast(null as {{ dbt.type_string() }})
    from openfigi, lateral flatten(input => openfigi.share_class_id_array) as f

    union all

    select
        'permid_security_id',
        permid.permid_security_id,
        permid.security_name,
        permid.asset_class,
        permid.primary_ticker,
        permid.primary_exchange_code
    from permid

    union all

    select
        'permid_quote_id',
        cast(f.value as {{ dbt.type_string() }}),
        permid.security_name,
        permid.asset_class,
        permid.primary_ticker,
        permid.primary_exchange_code
    from permid, lateral flatten(input => permid.quote_id_array) as f

),

-- A FIGI can appear under more than one reference row. Collapse to one row per
-- (type, value) so the join below cannot change the grain of the fact table.
security_lookup_deduplicated as (

    select
        security_id_type,
        security_id,
        max(security_name)   as reference_security_name,
        max(asset_class)     as asset_class,
        max(primary_ticker)  as primary_ticker,
        max(exchange_code)   as exchange_code
    from security_lookup
    where security_id is not null
    group by security_id_type, security_id

)

select
    {{ dbt.hash(
        "company_securities.company_id || '|' || company_securities.security_id_type || '|' || company_securities.security_id"
    ) }} as company_security_sk,

    company_securities.company_id,
    company_securities.security_id_type,
    company_securities.security_id,
    coalesce(
        company_securities.security_name,
        security_lookup_deduplicated.reference_security_name
    ) as security_name,
    security_lookup_deduplicated.asset_class,
    security_lookup_deduplicated.primary_ticker,
    security_lookup_deduplicated.exchange_code,
    security_lookup_deduplicated.security_id is not null as is_resolved

from company_securities
left join security_lookup_deduplicated
    on  company_securities.security_id_type = security_lookup_deduplicated.security_id_type
    and company_securities.security_id      = security_lookup_deduplicated.security_id

{{ config(enabled = var('snoco_company_enabled', true)) }}

-- The company spine. One row per company, unique on company_id.
--
-- entity_level is dropped: it is the constant 'Corporate' on all 2.9M rows.
-- global_tickers is dropped: it is an ARRAY that is NULL on all 2.9M rows.
-- Neither is an oversight; see docs/DISCOVERY.md trap 4.
--
-- lei and the ticker arrays are passed through as ARRAY and flattened
-- downstream in int_snoco__company_identifiers, where the fan-out guard lives.

select
    cast(company_id            as {{ dbt.type_string() }}) as company_id,
    cast(company_name          as {{ dbt.type_string() }}) as company_name,
    cast(ein                   as {{ dbt.type_string() }}) as ein,
    cast(cik                   as {{ dbt.type_string() }}) as cik,
    lei                                                    as lei_array,
    cast(permid_company_id     as {{ dbt.type_string() }}) as permid_company_id,
    cast(primary_ticker        as {{ dbt.type_string() }}) as primary_ticker,
    cast(primary_exchange_code as {{ dbt.type_string() }}) as primary_exchange_code,
    cast(primary_exchange_name as {{ dbt.type_string() }}) as primary_exchange_name

from {{ source('snoco', 'company_index') }}

{{ config(enabled = var('snoco_securities_enabled', true)) }}

-- OpenFIGI security reference, 119,273 rows.
--
-- The identifier columns are ARRAYs and are passed through as such. Resolving
-- a company_security_relationships.security_id against them needs
-- ARRAY_CONTAINS, not equality. global_tickers here IS populated, unlike the
-- identically named column on company_index.

select
    cast(top_level_openfigi_id      as {{ dbt.type_string() }}) as openfigi_id,
    cast(top_level_openfigi_id_type as {{ dbt.type_string() }}) as openfigi_id_type,
    cast(primary_ticker             as {{ dbt.type_string() }}) as primary_ticker,
    cast(security_name              as {{ dbt.type_string() }}) as security_name,
    cast(asset_class                as {{ dbt.type_string() }}) as asset_class,
    security_type                                               as security_type_array,
    global_tickers                                              as global_tickers_array,
    openfigi_figi_id                                            as figi_id_array,
    openfigi_composite_id                                       as composite_id_array,
    openfigi_share_class_id                                     as share_class_id_array,
    exchange_codes                                              as exchange_codes_array

from {{ source('snoco', 'openfigi_security_index') }}
where top_level_openfigi_id is not null

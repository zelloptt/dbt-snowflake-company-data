{{ config(enabled = var('snoco_securities_enabled', true)) }}

-- PermID security reference, 25,751 rows.
--
-- permid_security_id is scalar and joins by equality; permid_quote_id is an
-- ARRAY and needs ARRAY_CONTAINS.

select
    cast(permid_security_id     as {{ dbt.type_string() }}) as permid_security_id,
    cast(primary_ticker         as {{ dbt.type_string() }}) as primary_ticker,
    cast(security_name          as {{ dbt.type_string() }}) as security_name,
    cast(asset_class            as {{ dbt.type_string() }}) as asset_class,
    cast(primary_exchange_code  as {{ dbt.type_string() }}) as primary_exchange_code,
    cast(primary_exchange_name  as {{ dbt.type_string() }}) as primary_exchange_name,
    cast(security_status        as {{ dbt.type_string() }}) as security_status,
    permid_quote_id                                         as quote_id_array,
    global_tickers                                          as global_tickers_array

from {{ source('snoco', 'permid_security_index') }}
where permid_security_id is not null

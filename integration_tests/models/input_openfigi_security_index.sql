-- Same reason as input_company_index: five of these columns are ARRAYs.
select
    top_level_openfigi_id,
    top_level_openfigi_id_type,
    primary_ticker,
    security_name,
    asset_class,
    split(security_type_raw, '|')          as security_type,
    split(global_tickers_raw, '|')         as global_tickers,
    split(openfigi_figi_id_raw, '|')       as openfigi_figi_id,
    split(openfigi_composite_id_raw, '|')  as openfigi_composite_id,
    split(openfigi_share_class_id_raw, '|') as openfigi_share_class_id,
    split(exchange_codes_raw, '|')         as exchange_codes
from {{ ref('snoco_seed_openfigi_security_index') }}

select
    permid_security_id,
    primary_ticker,
    security_name,
    asset_class,
    primary_exchange_code,
    primary_exchange_name,
    security_status,
    split(permid_quote_id_raw, '|') as permid_quote_id,
    split(global_tickers_raw, '|')  as global_tickers
from {{ ref('snoco_seed_permid_security_index') }}

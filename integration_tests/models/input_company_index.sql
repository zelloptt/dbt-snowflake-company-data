-- A seed cannot hold an ARRAY, and COMPANY_INDEX.LEI is one. This turns the
-- pipe-delimited lei_raw column into a real ARRAY so the package's staging
-- model sees the same type it sees against the live share.
--
-- Existing only because the package addresses every source through a relation
-- var: pointing snoco_company_index at this model instead of at the seed needs
-- no change to package code.

select
    company_id,
    company_name,
    entity_level,
    ein,
    cik,
    case when nullif(lei_raw, '') is null then null else split(lei_raw, '|') end as lei,
    permid_company_id,
    primary_ticker,
    primary_exchange_code,
    primary_exchange_name,
    cast(null as array) as global_tickers   -- NULL on every row of the real object
from {{ ref('snoco_seed_company_index') }}

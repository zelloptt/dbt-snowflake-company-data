-- The consumer-side table the matching layer is pointed at. A model rather than
-- a bare seed so the suite also proves snoco__match_source accepts a model name
-- resolved through ref().
select account_id, account_name, website
from {{ ref('snoco_seed_crm_accounts') }}

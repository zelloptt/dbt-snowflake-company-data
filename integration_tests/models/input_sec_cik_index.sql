-- The seed cannot hold both NULL and '' in one CSV. Fusion also rejects
-- empty_as_null (dbt_project nested boolean, and the same key in seed YAML).
-- Orphan filers need a NULL company_id (trap 3, 28.7% of the real object);
-- C5 needs a literal empty-string country and state so coalesce cannot prefer
-- a blank over EAV (trap 8). Empty CSV fields load as NULL. C5's blanks are
-- the sentinel __EMPTY__, turned into '' here. Orphan company_id fields stay
-- empty in the CSV and arrive as NULL, matching the live share.

select
    cik,
    nullif(company_id, '') as company_id,
    company_name,
    ein,
    sic,
    sic_code_category,
    sic_code_description,
    sec_filer_category,
    incorporation_state,
    incorporation_country,
    address_line_1,
    address_line_2,
    city,
    iff(state = '__EMPTY__', '', state) as state,
    zip,
    iff(country = '__EMPTY__', '', country) as country,
    country_geo_id,
    state_geo_id,
    phone_number
from {{ ref('snoco_seed_sec_cik_index') }}

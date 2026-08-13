-- The seed cannot hold both NULL and '' under one empty_as_null setting.
-- Orphan filers need a NULL company_id (trap 3, 28.7% of the real object);
-- C5 needs a literal empty-string country and state so coalesce cannot prefer
-- a blank over EAV (trap 8). The seed therefore loads empties as '', and this
-- wrapper turns company_id '' back into NULL the way the live share stores it.

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
    state,
    zip,
    country,
    country_geo_id,
    state_geo_id,
    phone_number
from {{ ref('snoco_seed_sec_cik_index') }}

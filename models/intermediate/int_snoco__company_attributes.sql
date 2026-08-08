{{ config(enabled = var('snoco_company_enabled', true)) }}

-- Pivot the entity-attribute-value table to one row per company.
--
-- Two things have to be handled explicitly, and neither is obvious from the
-- source:
--
-- 1. The table is NOT unique on (company_id, attribute_name). 11,745,288 rows
--    carry 11,471,303 distinct pairs. There are no exact duplicate rows; the
--    excess comes from 1,918 company/attribute pairs holding more than one
--    distinct value, of which 1,913 are `lei`.
--
-- 2. relationship_end_date is NULL on every row, so there is no close-out to
--    filter on. `where end_date is null` would look like deduplication while
--    doing nothing at all.
--
-- So the winner is picked deterministically: most recently observed first, then
-- by value as a tiebreak so the result is stable across runs rather than
-- dependent on scan order. max() would also collapse the duplicates but would
-- silently prefer the lexically largest value, which is not the same thing as
-- the most recent one.

with ranked as (

    select
        company_id,
        attribute_name,
        attribute_value,
        row_number() over (
            partition by company_id, attribute_name
            order by observed_from_date desc nulls last, attribute_value
        ) as value_rank

    from {{ ref('stg_snoco__company_characteristics') }}
    where attribute_value is not null

),

deduplicated as (

    select company_id, attribute_name, attribute_value
    from ranked
    where value_rank = 1

)

select
    company_id,

    max(case when attribute_name = 'company_name'             then attribute_value end) as company_name,
    max(case when attribute_name = 'company_legal_structure'  then attribute_value end) as legal_structure,

    max(case when attribute_name = 'sic_code'                 then attribute_value end) as sic_code,
    max(case when attribute_name = 'sic_description'          then attribute_value end) as sic_description,
    max(case when attribute_name = 'sec_industry_group'       then attribute_value end) as sec_industry_group,

    max(case when attribute_name = 'business_address_line1'   then attribute_value end) as address_line_1,
    max(case when attribute_name = 'business_address_line2'   then attribute_value end) as address_line_2,
    max(case when attribute_name = 'business_address_city'    then attribute_value end) as city,
    max(case when attribute_name = 'business_address_state'   then attribute_value end) as state,
    max(case when attribute_name = 'business_address_zip'     then attribute_value end) as postal_code,
    max(case when attribute_name = 'business_address_country' then attribute_value end) as country,

    max(case when attribute_name = 'ein'                      then attribute_value end) as ein,
    max(case when attribute_name = 'cik'                      then attribute_value end) as cik,
    max(case when attribute_name = 'lei'                      then attribute_value end) as lei,
    max(case when attribute_name = 'permid_company_id'        then attribute_value end) as permid_company_id

from deduplicated
group by company_id

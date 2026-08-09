{{ config(enabled = var('snoco_company_enabled', true)) }}

-- Parent and subsidiary edges, 848 rows.
--
-- The share stores each of the 424 real relationships twice, once as 'Parent'
-- and once as 'Subsidiary'. Both directions are kept here so the staging model
-- stays a faithful rename of the source; int_snoco__company_edges picks one
-- direction to build the hierarchy from.

select
    cast(company_id           as {{ dbt.type_string() }}) as company_id,
    cast(related_company_id   as {{ dbt.type_string() }}) as related_company_id,
    cast(relationship_type    as {{ dbt.type_string() }}) as relationship_type,
    cast(relationship_start_date as date)                 as observed_from_date

from {{ var('snoco_company_relationships') }}
where company_id is not null
  and related_company_id is not null
  -- a self-edge would make the recursive hierarchy loop forever
  and company_id != related_company_id

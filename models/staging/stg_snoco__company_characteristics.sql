{{ config(enabled = var('snoco_company_enabled', true)) }}

-- Entity-attribute-value attributes, 11.7M rows across 15 attribute names.
--
-- relationship_end_date is dropped rather than exposed. It is NULL on every
-- row, so carrying it forward invites the reasonable-looking filter
-- `where relationship_end_date is null`, which does nothing while reading as
-- though it selects current records. See docs/DISCOVERY.md trap 2.

select
    cast(company_id              as {{ dbt.type_string() }}) as company_id,
    cast(relationship_type       as {{ dbt.type_string() }}) as attribute_name,
    cast(value                   as {{ dbt.type_string() }}) as attribute_value,
    cast(relationship_start_date as date)                    as observed_from_date

from {{ var('snoco_company_characteristics') }}
where company_id is not null
  and relationship_type is not null

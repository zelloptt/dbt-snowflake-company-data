{{ config(enabled = var('snoco_company_enabled', true)) }}

-- Company to owned web domain. Many-to-many in both directions: 319,269 rows
-- carry 289,774 distinct domains across 315,950 distinct companies.
--
-- The provider already normalises these (no scheme, no www., no path); only 65
-- rows carry a slash or a scheme. Those are cleaned rather than dropped, so the
-- domain match key is uniformly shaped.

with source as (

    select
        cast(company_id as {{ dbt.type_string() }}) as company_id,
        cast(domain_id  as {{ dbt.type_string() }}) as domain_raw,
        cast(relationship_start_date as date)       as observed_from_date

    from {{ source('snoco', 'company_domain_relationships') }}
    where company_id is not null
      and domain_id is not null

)

select
    company_id,
    domain_raw,
    -- strip scheme, then any www. prefix, then anything from the first slash
    lower(
        split_part(
            regexp_replace(
                regexp_replace(trim(domain_raw), '^[a-zA-Z][a-zA-Z0-9+.-]*://', ''),
                '^www\\.', ''
            ),
            '/', 1
        )
    ) as domain,
    observed_from_date

from source

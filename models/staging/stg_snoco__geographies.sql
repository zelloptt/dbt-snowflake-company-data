{{ config(enabled = var('snoco_geography_enabled', true)) }}

-- Geographic entity index, 573,277 rows, unique on geo_id, spanning country
-- down to census block group.
--
-- Kept unfiltered. sec_cik_index carries geo ids at country, state and zip
-- level, so narrowing this to country would break resolution for the others.

select
    cast(geo_id           as {{ dbt.type_string() }}) as geo_id,
    cast(geo_name         as {{ dbt.type_string() }}) as geo_name,
    cast(level            as {{ dbt.type_string() }}) as geo_level,
    cast(iso_name         as {{ dbt.type_string() }}) as iso_name,
    cast(iso_alpha2       as {{ dbt.type_string() }}) as iso_alpha2,
    cast(iso_alpha3       as {{ dbt.type_string() }}) as iso_alpha3,
    cast(iso_3166_2_code  as {{ dbt.type_string() }}) as iso_3166_2_code

from {{ var('snoco_geography_index') }}
where geo_id is not null

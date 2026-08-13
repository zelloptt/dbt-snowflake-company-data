{{ config(enabled = var('snoco_sec_enabled', true)) }}

-- SEC filer registry, 981,128 rows, unique on cik.
--
-- Keyed on cik, not company_id: 281,823 rows (28.7%) carry a NULL company_id
-- and cannot be joined to the spine. Those rows are kept here on purpose so
-- this model stays a complete picture of the filer universe. Only the
-- company-level marts join to the spine, and they lose those rows knowingly.
-- See docs/DISCOVERY.md trap 3.
--
-- The industry column is `sic`. There is no `sic_code` column on this object;
-- `sic_code` is an attribute_name in company_characteristics, which is a
-- different thing carrying different coverage.
--
-- `country` and `state` are EDGAR state-or-country codes, not ISO, and they
-- carry empty strings. Staging passes them through; snoco__companies turns
-- blanks and XX into NULL and resolves ISO via the *_geo_id columns. See
-- docs/DISCOVERY.md trap 8.

select
    cast(cik                    as {{ dbt.type_string() }}) as cik,
    cast(company_id             as {{ dbt.type_string() }}) as company_id,
    cast(company_name           as {{ dbt.type_string() }}) as company_name,
    cast(ein                    as {{ dbt.type_string() }}) as ein,

    cast(sic                    as {{ dbt.type_string() }}) as sic_code,
    cast(sic_code_category      as {{ dbt.type_string() }}) as sic_category,
    cast(sic_code_description   as {{ dbt.type_string() }}) as sic_description,
    cast(sec_filer_category     as {{ dbt.type_string() }}) as sec_filer_category,

    cast(incorporation_state    as {{ dbt.type_string() }}) as incorporation_state,
    cast(incorporation_country  as {{ dbt.type_string() }}) as incorporation_country,

    cast(address_line_1         as {{ dbt.type_string() }}) as address_line_1,
    cast(address_line_2         as {{ dbt.type_string() }}) as address_line_2,
    cast(city                   as {{ dbt.type_string() }}) as city,
    cast(state                  as {{ dbt.type_string() }}) as state,
    cast(zip                    as {{ dbt.type_string() }}) as postal_code,
    cast(country                as {{ dbt.type_string() }}) as country,
    cast(country_geo_id         as {{ dbt.type_string() }}) as country_geo_id,
    cast(state_geo_id           as {{ dbt.type_string() }}) as state_geo_id,
    cast(phone_number           as {{ dbt.type_string() }}) as phone_number

from {{ var('snoco_sec_cik_index') }}
where cik is not null

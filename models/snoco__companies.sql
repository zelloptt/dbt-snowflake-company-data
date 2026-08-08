{{ config(enabled = var('snoco_company_enabled', true)) }}

{%- set sec_enabled = var('snoco_sec_enabled', true) -%}
{%- set geo_enabled = var('snoco_geography_enabled', true) -%}

-- Each record represents one company in the Snowflake Public Data (Free)
-- spine, with its attributes resolved from the entity-attribute-value table and
-- enriched, where available, from the SEC filer registry.
--
-- Grain: one row per company_id. 2,918,929 rows.
--
-- The join to the SEC filer registry is one-to-one and verified so: of
-- SEC_CIK_INDEX's 981,128 rows, 699,305 carry a non-null company_id and those
-- are 699,305 distinct values. The other 281,823 filers cannot be attached to
-- any company and are absent here by necessity; stg_snoco__sec_filers keeps
-- them if you need the full filer universe.
--
-- Attribute coverage is thin and that is the dataset, not a modelling failure.
-- Roughly 24% of companies have an address, 4% an industry group, and 1% an
-- SIC code. Nothing here carries employee count or revenue because the free
-- share contains neither.

with spine as (

    select * from {{ ref('stg_snoco__company_index') }}

),

attributes as (

    select * from {{ ref('int_snoco__company_attributes') }}

),

{% if sec_enabled %}
sec_filers as (

    select * from {{ ref('stg_snoco__sec_filers') }}
    where company_id is not null

),
{% endif %}

{% if geo_enabled %}
countries as (

    select geo_id, iso_alpha2, iso_alpha3, geo_name
    from {{ ref('stg_snoco__geographies') }}
    where geo_level = 'Country'

),
{% endif %}

joined as (

    select
        spine.company_id,

        -- company_index and the EAV table both carry a name. They agree on the
        -- overwhelming majority of rows; index wins because it is the spine.
        coalesce(spine.company_name, attributes.company_name) as company_name,
        attributes.legal_structure,

        spine.ein,
        spine.cik,
        spine.permid_company_id,
        spine.primary_ticker,
        spine.primary_exchange_code,
        spine.primary_exchange_name,

        {% if sec_enabled %}
        -- SEC's SIC is both better populated and better described than the EAV
        -- copy, so it leads; the EAV value fills the gaps.
        coalesce(sec_filers.sic_code, attributes.sic_code)       as sic_code,
        coalesce(sec_filers.sic_description, attributes.sic_description) as sic_description,
        sec_filers.sic_category,
        sec_filers.sec_filer_category,
        sec_filers.incorporation_state,
        sec_filers.incorporation_country,
        sec_filers.cik is not null                               as is_sec_filer,
        {% else %}
        attributes.sic_code,
        attributes.sic_description,
        cast(null as {{ dbt.type_string() }})                    as sic_category,
        cast(null as {{ dbt.type_string() }})                    as sec_filer_category,
        cast(null as {{ dbt.type_string() }})                    as incorporation_state,
        cast(null as {{ dbt.type_string() }})                    as incorporation_country,
        cast(null as boolean)                                    as is_sec_filer,
        {% endif %}

        attributes.sec_industry_group,

        {% if sec_enabled %}
        coalesce(sec_filers.address_line_1, attributes.address_line_1) as address_line_1,
        coalesce(sec_filers.address_line_2, attributes.address_line_2) as address_line_2,
        coalesce(sec_filers.city,           attributes.city)           as city,
        coalesce(sec_filers.state,          attributes.state)          as state,
        coalesce(sec_filers.postal_code,    attributes.postal_code)    as postal_code,
        coalesce(sec_filers.country,        attributes.country)        as country,
        sec_filers.country_geo_id,
        sec_filers.phone_number,
        {% else %}
        attributes.address_line_1,
        attributes.address_line_2,
        attributes.city,
        attributes.state,
        attributes.postal_code,
        attributes.country,
        cast(null as {{ dbt.type_string() }})                    as country_geo_id,
        cast(null as {{ dbt.type_string() }})                    as phone_number,
        {% endif %}

        {% if geo_enabled and sec_enabled %}
        countries.iso_alpha2                                     as country_iso_alpha2,
        countries.iso_alpha3                                     as country_iso_alpha3
        {% else %}
        cast(null as {{ dbt.type_string() }})                    as country_iso_alpha2,
        cast(null as {{ dbt.type_string() }})                    as country_iso_alpha3
        {% endif %}

    from spine
    left join attributes on spine.company_id = attributes.company_id
    {% if sec_enabled %}
    left join sec_filers on spine.company_id = sec_filers.company_id
    {% endif %}
    {% if geo_enabled and sec_enabled %}
    left join countries  on sec_filers.country_geo_id = countries.geo_id
    {% endif %}

)

select
    *,
    {{ snowflake_company_data.normalize_company_name('company_name') }} as company_name_normalized
from joined

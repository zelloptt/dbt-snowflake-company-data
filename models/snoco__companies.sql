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
--
-- Country and state on the source are EDGAR state-or-country codes, not ISO
-- and not one vocabulary. Filter on country_iso_alpha2 / state_iso_3166_2,
-- which resolve through geography_index. The EDGAR values are kept as
-- edgar_country_code / edgar_state_code and named from the SEC list shipped
-- as snoco_edgar_state_country_codes. See docs/DISCOVERY.md trap 8.

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

states as (

    select geo_id, iso_3166_2_code, geo_name
    from {{ ref('stg_snoco__geographies') }}
    where geo_level = 'State'

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
        nullif(trim(sec_filers.incorporation_state), '')         as incorporation_state,
        nullif(trim(sec_filers.incorporation_country), '')       as incorporation_country,
        sec_filers.cik is not null                               as is_sec_filer,
        {% else %}
        attributes.sic_code,
        attributes.sic_description,
        cast(null as {{ dbt.type_string() }})                    as sic_category,
        cast(null as {{ dbt.type_string() }})                    as sec_filer_category,
        cast(null as {{ dbt.type_string() }})                    as incorporation_state,
        cast(null as {{ dbt.type_string() }})                    as incorporation_country,
        cast(null as {{ dbt.type_boolean() }})                   as is_sec_filer,
        {% endif %}

        attributes.sec_industry_group,

        {% if sec_enabled %}
        -- Empty strings are not NULLs. coalesce() prefers a blank SEC value
        -- over a real EAV one, and `where country is not null` then returns
        -- junk. Null blanks (and the EDGAR XX placeholder) on each source
        -- before coalescing. Same filter the domains and identifiers models
        -- already apply.
        coalesce(nullif(trim(sec_filers.address_line_1), ''), nullif(trim(attributes.address_line_1), '')) as address_line_1,
        coalesce(nullif(trim(sec_filers.address_line_2), ''), nullif(trim(attributes.address_line_2), '')) as address_line_2,
        coalesce(nullif(trim(sec_filers.city), ''),           nullif(trim(attributes.city), ''))           as city,
        coalesce(nullif(trim(sec_filers.postal_code), ''),    nullif(trim(attributes.postal_code), ''))    as postal_code,
        nullif(trim(sec_filers.phone_number), '')            as phone_number,
        {% else %}
        nullif(trim(attributes.address_line_1), '')          as address_line_1,
        nullif(trim(attributes.address_line_2), '')          as address_line_2,
        nullif(trim(attributes.city), '')                    as city,
        nullif(trim(attributes.postal_code), '')             as postal_code,
        cast(null as {{ dbt.type_string() }})                as phone_number,
        {% endif %}

        {% if geo_enabled and sec_enabled %}
        -- These are the country/state columns to filter on. Resolved via
        -- geography_index, independent of whatever EDGAR code the row carries.
        -- A filer with country = 'XX' still gets US here if country_geo_id
        -- points at the United States.
        countries.iso_alpha2                                 as country_iso_alpha2,
        countries.iso_alpha3                                 as country_iso_alpha3,
        countries.geo_name                                   as country_name,
        states.iso_3166_2_code                               as state_iso_3166_2,
        states.geo_name                                      as state_name,
        {% else %}
        cast(null as {{ dbt.type_string() }})                as country_iso_alpha2,
        cast(null as {{ dbt.type_string() }})                as country_iso_alpha3,
        cast(null as {{ dbt.type_string() }})                as country_name,
        cast(null as {{ dbt.type_string() }})                as state_iso_3166_2,
        cast(null as {{ dbt.type_string() }})                as state_name,
        {% endif %}

        {% if sec_enabled %}
        sec_filers.country_geo_id,
        sec_filers.state_geo_id,
        coalesce(
            case
                when upper(trim(sec_filers.country)) in ('', 'XX') then null
                else trim(sec_filers.country)
            end,
            case
                when upper(trim(attributes.country)) in ('', 'XX') then null
                else trim(attributes.country)
            end
        )                                                    as edgar_country_code,
        coalesce(
            case
                when upper(trim(sec_filers.state)) in ('', 'XX') then null
                else trim(sec_filers.state)
            end,
            case
                when upper(trim(attributes.state)) in ('', 'XX') then null
                else trim(attributes.state)
            end
        )                                                    as edgar_state_code
        {% else %}
        cast(null as {{ dbt.type_string() }})                as country_geo_id,
        cast(null as {{ dbt.type_string() }})                as state_geo_id,
        case
            when upper(trim(attributes.country)) in ('', 'XX') then null
            else trim(attributes.country)
        end                                                  as edgar_country_code,
        case
            when upper(trim(attributes.state)) in ('', 'XX') then null
            else trim(attributes.state)
        end                                                  as edgar_state_code
        {% endif %}

    from spine
    left join attributes on spine.company_id = attributes.company_id
    {% if sec_enabled %}
    left join sec_filers on spine.company_id = sec_filers.company_id
    {% endif %}
    {% if geo_enabled and sec_enabled %}
    left join countries  on sec_filers.country_geo_id = countries.geo_id
    left join states     on sec_filers.state_geo_id   = states.geo_id
    {% endif %}

)

select
    joined.*,
    edgar_countries.edgar_name as edgar_country_name,
    edgar_states.edgar_name    as edgar_state_name,
    {{ snowflake_company_data.normalize_company_name('company_name') }} as company_name_normalized
from joined
left join {{ ref('snoco_edgar_state_country_codes') }} as edgar_countries
    on upper(joined.edgar_country_code) = edgar_countries.edgar_code
left join {{ ref('snoco_edgar_state_country_codes') }} as edgar_states
    on upper(joined.edgar_state_code) = edgar_states.edgar_code

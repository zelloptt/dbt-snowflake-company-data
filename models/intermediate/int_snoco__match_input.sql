{%- set matching_enabled = var('snoco_matching_enabled', false) -%}

{{ config(
    enabled = matching_enabled,
    materialized = 'ephemeral'
) }}

-- Each record represents one of the consumer's records, normalised into the
-- shape the matching models expect. Ephemeral: it exists to keep the column
-- mapping in one place rather than repeating it in both matching models.
--
-- The whole body is behind `matching_enabled`. dbt renders a model's SQL during
-- parsing even when config(enabled=false), so an unguarded
-- raise_compiler_error here would fail every project that installs this package
-- without configuring matching, which is the default and by far the common case.
--
-- The `{% raw %}{% if %}{% endraw %}` below deliberately does not strip surrounding whitespace.
-- With `{% raw %}{%- if ... -%}{% endraw %}` the newline after this comment block is consumed and
-- `select` lands on the same line as `--`, which comments out the query.

{% if matching_enabled %}

{%- set match_source   = var('snoco__match_source') -%}
{%- set id_column      = var('snoco__match_id_column') -%}
{%- set name_column    = var('snoco__match_name_column') -%}
{%- set domain_column  = var('snoco__match_domain_column') -%}

{#-
    Fail at compile time naming the var, rather than letting Snowflake report a
    syntax error on a half-rendered select. These vars are declared as null in
    dbt_project.yml, so var(x, fallback) cannot reach a fallback and every check
    has to be an explicit truthiness test.
-#}
{%- if not match_source -%}
    {{ exceptions.raise_compiler_error(
        "snoco_matching_enabled is true but snoco__match_source is not set. "
        ~ "Set it to a model name (resolved with ref()) or to a fully qualified "
        ~ "relation such as 'analytics.crm.dim_accounts'."
    ) }}
{%- endif -%}
{%- if not id_column -%}
    {{ exceptions.raise_compiler_error(
        "snoco_matching_enabled is true but snoco__match_id_column is not set. "
        ~ "The matching layer needs a stable key on your side to return results against."
    ) }}
{%- endif -%}
{%- if not name_column and not domain_column -%}
    {{ exceptions.raise_compiler_error(
        "snoco_matching_enabled is true but neither snoco__match_name_column nor "
        ~ "snoco__match_domain_column is set. There is nothing to match on."
    ) }}
{%- endif -%}

{#-
    A dotted value is treated as an already-qualified relation; anything else is
    a model name resolved with ref(). Supporting both matters because the records
    people want to match are as often a raw CRM table as a modelled one, and
    forcing a wrapper model for the former is friction for no benefit.
-#}
{%- if '.' in match_source -%}
    {%- set match_relation = match_source -%}
{%- else -%}
    {%- set match_relation = ref(match_source) -%}
{%- endif -%}

select
    cast({{ id_column }} as {{ dbt.type_string() }}) as match_input_id,

    {% if name_column %}
    cast({{ name_column }} as {{ dbt.type_string() }}) as match_input_name,
    {{ snowflake_company_data.normalize_company_name(name_column) }} as match_input_name_normalized,
    {% else %}
    cast(null as {{ dbt.type_string() }}) as match_input_name,
    cast(null as {{ dbt.type_string() }}) as match_input_name_normalized,
    {% endif %}

    {% if domain_column %}
    lower(
        split_part(
            regexp_replace(
                regexp_replace(trim(cast({{ domain_column }} as {{ dbt.type_string() }})),
                    '^[a-zA-Z][a-zA-Z0-9+.-]*://', ''),
                '^www\\.', ''
            ),
            '/', 1
        )
    ) as match_input_domain
    {% else %}
    cast(null as {{ dbt.type_string() }}) as match_input_domain
    {% endif %}

from {{ match_relation }}
where {{ id_column }} is not null

{% else %}

-- Disabled. Column-compatible stub so parsing succeeds.
select
    cast(null as {{ dbt.type_string() }}) as match_input_id,
    cast(null as {{ dbt.type_string() }}) as match_input_name,
    cast(null as {{ dbt.type_string() }}) as match_input_name_normalized,
    cast(null as {{ dbt.type_string() }}) as match_input_domain
where false

{% endif %}

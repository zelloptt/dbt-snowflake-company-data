{% macro normalize_domain(column_name) -%}
{#-
    Reduce a URL or hostname to a bare registrable domain for matching:
    lowercase, no scheme, no `www.` prefix, no path.

    ORDER MATTERS AND IS THE WHOLE POINT OF THIS MACRO EXISTING.

    `lower()` must be applied FIRST, not wrapped around the result. Snowflake's
    REGEXP_REPLACE is case-sensitive by default, so stripping `^www\.` before
    lowercasing leaves `WWW.Acme.com` as `www.acme.com` instead of `acme.com`.
    That is silent: the value looks normalised, and it simply never matches
    anything on the deterministic domain join. CRM exports are full of
    capitalised hostnames, so this is the common case, not an edge case.

    This lived inline in two models and was wrong in both. It is a macro now so
    the package normalises a domain in exactly one place.

    Usage:
        {{ snowflake_company_data.normalize_domain('website') }}
-#}
nullif(
    split_part(
        regexp_replace(
            regexp_replace(
                lower(trim(cast({{ column_name }} as {{ dbt.type_string() }}))),
                '^[a-z][a-z0-9+.-]*://', ''
            ),
            '^www\\.', ''
        ),
        '/', 1
    ),
    ''
)
{%- endmacro %}

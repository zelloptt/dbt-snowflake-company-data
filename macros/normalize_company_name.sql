{% macro normalize_company_name(column_name) -%}
{#-
    Reduce a company name to a comparable form for matching.

    Lowercase, `&` to ` and `, drop everything that is not a letter, digit or
    space, collapse whitespace, then strip trailing legal-form words. Returns
    NULL rather than an empty string when nothing survives, so a name that is
    entirely punctuation does not become a match magnet.

    For matching and blocking only. Never for display.

    Usage:
        {{ snowflake_company_data.normalize_company_name('company_name') }}

    Configure with `snoco__legal_suffixes` to replace the built-in suffix list,
    for example when matching non-US entities. Setting it replaces the list
    rather than extending it.
-#}
{%- set base -%}
regexp_replace(
    regexp_replace(
        regexp_replace(
            lower(trim(cast({{ column_name }} as {{ dbt.type_string() }}))),
            '&', ' and '
        ),
        '[^a-z0-9 ]', ' '
    ),
    '[ ]+', ' '
)
{%- endset -%}
nullif(trim({{ snowflake_company_data._strip_legal_suffixes(base) }}), '')
{%- endmacro %}


{% macro _strip_legal_suffixes(expression) -%}
{#-
    Remove trailing legal-form words from an already-normalised name.

    Applied three times rather than once, because names routinely end in more
    than one: "acme holdings inc" needs two passes and "acme group holdings inc"
    needs three. A fourth pass has never changed a result on this dataset and
    costs a regexp_replace per row.

    Private. Called by normalize_company_name.
-#}
{%- set configured = var('snoco__legal_suffixes', []) -%}
{%- set default_suffixes = [
    'incorporated', 'corporation', 'company', 'limited',
    'inc', 'corp', 'co', 'ltd', 'llc', 'llp', 'lp', 'plc', 'pllc',
    'gmbh', 'ag', 'nv', 'bv', 'sa', 'sas', 'sarl', 'srl', 'spa', 'ab', 'as', 'oy',
    'pty', 'pte', 'kk', 'kg', 'ohg', 'snc',
    'holdings', 'holding', 'group'
] -%}
{#-
    var() cannot fall back here: snoco__legal_suffixes is declared as [] in
    dbt_project.yml, and a declared var is a defined var, so var(x, fallback)
    returns [] rather than the fallback. Resolve by truthiness instead.
-#}
{%- set suffixes = configured if configured else default_suffixes -%}
{%- set pattern = '( (' ~ suffixes | join('|') ~ '))+$' -%}
{#-
    The trailing-word pattern requires a preceding space, so a name that is
    ONLY legal-form words survives it: "Inc." normalises to "inc" and then
    matches every other company that reduces to "inc". Measured: five distinct
    companies collide on that one token, and a fuzzy scorer rates them all 1.0.

    A name carrying no information beyond its legal form cannot identify
    anybody, so the final pass anchors on the whole string and empties it.
    normalize_company_name wraps this in nullif, giving NULL, and the matching
    models skip NULL names entirely.
-#}
{%- set whole_string_pattern = '^(' ~ suffixes | join('|') ~ ')$' -%}
regexp_replace(
    trim(regexp_replace(trim(regexp_replace(trim(regexp_replace(
        {{ expression }}, '{{ pattern }}', '')), '{{ pattern }}', '')), '{{ pattern }}', '')),
    '{{ whole_string_pattern }}', ''
)
{%- endmacro %}

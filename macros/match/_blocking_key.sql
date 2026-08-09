{% macro _blocking_key(normalized_name) -%}
{#-
    Blocking key for fuzzy name matching.

    Fuzzy matching is a cross join. Against a 2.9M-row spine, comparing every
    input row to every company is not slow, it is impossible. Blocking cuts the
    candidate space to rows that share a cheap deterministic key, and only those
    pairs get scored.

    The key is the first four characters of the normalised name plus its word
    count. The prefix does the heavy lifting; the word count separates
    "acme" from "acme logistics services" without another string comparison.

    The cost of blocking is recall: two names that disagree in their first four
    characters can never match, so "int'l business machines" and "ibm" are
    unreachable this way. That is the accepted trade. Deterministic identifier
    matching runs first precisely because it does not have this limitation.

    Private. Called by the matching models.
-#}
left({{ normalized_name }}, 4)
    || '|'
    || cast(
        case
            when {{ normalized_name }} is null or {{ normalized_name }} = '' then 0
            else regexp_count({{ normalized_name }}, ' ') + 1
        end
        as {{ dbt.type_string() }}
    )
{%- endmacro %}

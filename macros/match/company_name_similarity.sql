{% macro company_name_similarity(left_name, right_name) -%}
{#-
    Similarity between two already-normalised company names, on 0..1.

    A blend of two Snowflake built-ins that fail in different directions:

      JAROWINKLER_SIMILARITY rewards a shared prefix, which is what you want for
      "acme logistics" vs "acme logistic" but is exactly what makes it rate
      "american airlines" against "american apparel" far too highly.

      EDITDISTANCE is prefix-blind and punishes length differences honestly, but
      is unbounded, so it needs normalising against the longer string before it
      can be compared to anything.

    Weighted 0.6 / 0.4 toward Jaro-Winkler, which handles the abbreviation and
    truncation cases that dominate real CRM data, with edit distance holding it
    back from the shared-prefix trap.

    TWO SNOWFLAKE TRAPS ARE HANDLED HERE, and both are silent if you miss them:

      1. JAROWINKLER_SIMILARITY returns an INTEGER 0..100, not a 0..1 float.
         Comparing it directly to snoco__match_min_score (0.90) makes every
         candidate pass, and the matching layer then returns garbage instead of
         erroring. It is divided by 100.0 below.

      2. EDITDISTANCE is a raw character count where lower is better and there
         is no upper bound. It is converted to a 0..1 score where higher is
         better and floored at 0.

    Usage:
        {{ snowflake_company_data.company_name_similarity('a.name_norm', 'b.name_norm') }}
-#}
(
    0.6 * (jarowinkler_similarity({{ left_name }}, {{ right_name }}) / 100.0)
  + 0.4 * greatest(
        0,
        1 - (
            editdistance({{ left_name }}, {{ right_name }})
            / nullif(greatest(length({{ left_name }}), length({{ right_name }})), 0)
        )
    )
)
{%- endmacro %}

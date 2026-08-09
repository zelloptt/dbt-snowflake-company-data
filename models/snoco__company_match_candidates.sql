{{ config(enabled = var('snoco_matching_enabled', false)) }}

{%- set min_score = var('snoco__match_min_score', 0.90) -%}
{%- set max_candidates = var('snoco__match_max_candidates', 5) -%}

-- Each record represents one plausible company for one of your records, with
-- the evidence that produced it. Review this; join snoco__company_match when
-- you want a single answer.
--
-- Grain: one row per match_input_id + company_id + match_method.
--
-- Two methods, deliberately kept separate rather than blended into one number:
--
--   domain  - deterministic. Your domain equals a domain the share attributes
--             to that company. Scored 1.0. Shared domains (a registrar or a
--             parent's domain covering many subsidiaries) are still emitted,
--             flagged by is_shared_domain, because dropping them would hide the
--             ambiguity rather than resolve it.
--
--   name    - fuzzy, blocked. Only companies sharing a blocking key with your
--             normalised name are scored at all. This bounds the work; it also
--             means two names disagreeing in their first four characters can
--             never match. That is why domain matching runs alongside it.
--
-- snoco__match_min_score applies to the name method only. A domain match is an
-- identity assertion, not a similarity, and thresholding it would be incoherent.

with match_input as (

    select * from {{ ref('int_snoco__match_input') }}

),

companies as (

    select
        company_id,
        company_name,
        company_name_normalized
    from {{ ref('snoco__companies') }}
    where company_name_normalized is not null

),

company_domains as (

    select * from {{ ref('snoco__company_domains') }}

),

domain_matches as (

    select
        match_input.match_input_id,
        company_domains.company_id,
        'domain'                                    as match_method,
        cast(1.0 as {{ dbt.type_float() }})          as match_score,
        company_domains.domain                      as match_evidence,
        company_domains.is_shared_domain
    from match_input
    inner join company_domains
        on match_input.match_input_domain = company_domains.domain
    where match_input.match_input_domain is not null
      and match_input.match_input_domain != ''

),

-- Blocking. Without this the name join is 2.9M companies times every input row.
blocked_pairs as (

    select
        match_input.match_input_id,
        companies.company_id,
        match_input.match_input_name_normalized,
        companies.company_name_normalized
    from match_input
    inner join companies
        on {{ snowflake_company_data._blocking_key('match_input.match_input_name_normalized') }}
         = {{ snowflake_company_data._blocking_key('companies.company_name_normalized') }}
    where match_input.match_input_name_normalized is not null

),

name_matches as (

    select
        match_input_id,
        company_id,
        'name' as match_method,
        cast(
            {{ snowflake_company_data.company_name_similarity(
                'match_input_name_normalized',
                'company_name_normalized'
            ) }} as {{ dbt.type_float() }}
        ) as match_score,
        company_name_normalized as match_evidence,
        cast(null as {{ dbt.type_boolean() }}) as is_shared_domain
    from blocked_pairs

),

combined as (

    select match_input_id, company_id, match_method, match_score, match_evidence, is_shared_domain
    from domain_matches

    union all

    select match_input_id, company_id, match_method, match_score, match_evidence, is_shared_domain
    from name_matches
    where match_score >= {{ min_score }}

),

-- candidate_rank counts COMPANIES, not rows.
--
-- One company can legitimately appear twice here, once per method: a domain hit
-- and a name hit for the same company is the strongest possible evidence. If
-- rank were per row, that corroboration would consume two of the
-- snoco__match_max_candidates slots and push a genuine alternative out, and
-- worse, snoco__company_match would read its own second row as a rival and
-- flag the row ambiguous when nothing is ambiguous at all.
per_company as (

    select
        match_input_id,
        company_id,
        max(match_score) as best_score,
        max(case when match_method = 'domain' then 1 else 0 end) as has_domain_evidence
    from combined
    group by match_input_id, company_id

),

company_ranked as (

    select
        match_input_id,
        company_id,
        row_number() over (
            partition by match_input_id
            -- domain before name at equal score, then a stable tiebreak on
            -- company_id so repeated runs return the same ordering
            order by best_score desc, has_domain_evidence desc, company_id
        ) as candidate_rank
    from per_company

)

select
    combined.match_input_id,
    combined.company_id,
    combined.match_method,
    combined.match_score,
    combined.match_evidence,
    combined.is_shared_domain,
    company_ranked.candidate_rank
from combined
inner join company_ranked
    on  combined.match_input_id = company_ranked.match_input_id
    and combined.company_id     = company_ranked.company_id
where company_ranked.candidate_rank <= {{ max_candidates }}

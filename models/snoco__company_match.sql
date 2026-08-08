{{ config(enabled = var('snoco_matching_enabled', false)) }}

{%- set ambiguity_margin = var('snoco__match_ambiguity_margin', 0.02) -%}

-- Each record represents the single best company for one of your records.
--
-- Grain: one row per match_input_id. Input rows with no candidate above the
-- threshold are absent rather than present with a null company_id, so a left
-- join from your own table gives you the unmatched set without a filter.
--
-- The winner is candidate_rank = 1 from snoco__company_match_candidates, which
-- orders by score, then domain evidence over name evidence, then company_id.
-- That last term is not decoration: without it two companies with identical
-- scores would tie and Snowflake would be free to return either one, so the
-- same input would resolve differently between runs and every downstream
-- snapshot would churn.
--
-- is_ambiguous flags rows where the runner-up scored within
-- snoco__match_ambiguity_margin of the winner. Those are the rows worth a human
-- look; the winner is still a real answer, just not a confident one.
--
-- Jinja set/if tags go ABOVE this comment block, never between it and the SQL.
-- A trailing `-%}` eats the newline and lands `with` on the `--` line, which
-- comments out the query and fails with a syntax error pointing somewhere else.

with candidates as (

    select * from {{ ref('snoco__company_match_candidates') }}

),

winners as (

    -- candidate_rank is per company, so rank 1 can still be two rows when the
    -- same company matched by both domain and name. Collapse to one, preferring
    -- the domain row because it is the stronger claim and carries
    -- is_shared_domain.
    select *
    from candidates
    where candidate_rank = 1
    qualify row_number() over (
        partition by match_input_id
        order by case when match_method = 'domain' then 0 else 1 end,
                 match_score desc
    ) = 1

),

runners_up as (

    -- rank 2 is a genuinely different company, because candidate_rank counts
    -- companies. Before that change this read the winner's own second row as a
    -- rival and flagged every domain-plus-name agreement as ambiguous, which is
    -- precisely backwards: that pattern is the strongest evidence there is.
    select
        match_input_id,
        max(match_score) as runner_up_score
    from candidates
    where candidate_rank = 2
    group by match_input_id

)

select
    winners.match_input_id,
    winners.company_id,
    winners.match_method,
    winners.match_score,
    winners.match_evidence,
    winners.is_shared_domain,
    runners_up.runner_up_score,
    coalesce(
        runners_up.runner_up_score >= winners.match_score - {{ ambiguity_margin }},
        false
    ) as is_ambiguous

from winners
left join runners_up
    on winners.match_input_id = runners_up.match_input_id

{{ config(enabled = var('snoco_matching_enabled', false)) }}

-- Fails if any match score falls outside 0..1.
--
-- This exists to catch one specific, silent, catastrophic mistake:
-- Snowflake's JAROWINKLER_SIMILARITY returns an INTEGER 0..100, not a 0..1
-- float. If the division by 100.0 in company_name_similarity is ever removed,
-- every candidate scores far above snoco__match_min_score, every threshold
-- passes, and the matching layer returns confident garbage instead of erroring.
--
-- A score above 1 is the only visible symptom, so it is worth a test of its own.

select
    match_input_id,
    company_id,
    match_method,
    match_score

from {{ ref('snoco__company_match_candidates') }}
where match_score is null
   or match_score < 0
   or match_score > 1

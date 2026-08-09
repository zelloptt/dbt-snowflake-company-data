-- The matching layer against a synthetic CRM table. Every row returned is a
-- failed assertion.

with expectations as (

    -- A1 matches on domain, which is deterministic and scored 1.0.
    select 'domain match wins and scores 1.0' as assertion, 1 as expected,
           (select count(*) from {{ ref('snoco__company_match') }}
            where match_input_id = 'A1' and company_id = 'C1'
              and match_method = 'domain' and match_score = 1.0) as actual
    union all
    -- A1's name also matches C1. That is corroboration, not ambiguity.
    select 'agreement across both methods is not ambiguous', 1,
           (select count(*) from {{ ref('snoco__company_match') }}
            where match_input_id = 'A1' and not is_ambiguous)
    union all
    -- A2 has no domain; "Borealis Freight Group Limited" must reach C2 on name
    -- alone once the legal suffixes are stripped.
    select 'name-only match resolves through suffix stripping', 1,
           (select count(*) from {{ ref('snoco__company_match') }}
            where match_input_id = 'A2' and company_id = 'C2' and match_method = 'name')
    union all
    -- A3's website is WWW.AURORAROBOTICS.MX. This is the case that silently
    -- failed before normalize_domain lowercased first.
    select 'uppercase input domain still matches', 1,
           (select count(*) from {{ ref('snoco__company_match') }}
            where match_input_id = 'A3' and company_id = 'C4' and match_method = 'domain')
    union all
    select 'unmatched input is absent rather than null', 0,
           (select count(*) from {{ ref('snoco__company_match') }} where match_input_id = 'A4')
    union all
    -- A5 is "Inc.", which normalises to nothing and must match nobody.
    select 'input that is only a legal form matches nothing', 0,
           (select count(*) from {{ ref('snoco__company_match') }} where match_input_id = 'A5')
    union all
    select 'one winner per matched input', 0,
           (select count(*) - count(distinct match_input_id) from {{ ref('snoco__company_match') }})
    union all
    select 'every score is within 0..1', 0,
           (select count(*) from {{ ref('snoco__company_match_candidates') }}
            where match_score < 0 or match_score > 1 or match_score is null)

)

select assertion, expected, actual
from expectations
where actual is distinct from expected

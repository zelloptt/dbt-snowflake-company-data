{{ config(enabled = var('snoco_company_enabled', true)) }}

-- Each record represents one web domain owned by one company.
--
-- Grain: one row per company_id + domain, enforced by a unique test on
-- company_domain_sk.
--
-- This is the highest-value join key in the package for CRM work, because a
-- domain is the one attribute a CRM record almost always has and almost never
-- gets wrong. It is also many-to-many in both directions: 319,269 rows carry
-- 289,774 distinct domains across 315,950 companies. is_shared_domain flags
-- the domains that resolve to more than one company, which are the ones that
-- will quietly fan out a naive join.

with domains as (

    select
        company_id,
        domain,
        min(observed_from_date) as first_observed_date
    from {{ ref('stg_snoco__company_domains') }}
    where domain is not null
      and domain != ''
    group by company_id, domain

),

domain_company_counts as (

    select
        domain,
        count(distinct company_id) as company_count
    from domains
    group by domain

)

select
    {{ dbt.hash("domains.company_id || '|' || domains.domain") }} as company_domain_sk,
    domains.company_id,
    domains.domain,
    domains.first_observed_date,
    domain_company_counts.company_count            as companies_sharing_domain,
    domain_company_counts.company_count > 1        as is_shared_domain

from domains
inner join domain_company_counts
    on domains.domain = domain_company_counts.domain

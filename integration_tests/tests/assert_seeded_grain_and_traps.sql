-- One test, several assertions, because they share a fixture and a failure in
-- any of them means the same thing: the package no longer handles a trap the
-- fixture was built to contain.
--
-- Each row returned is a failed assertion, named.

with expectations as (

    select 'companies row count' as assertion, 8 as expected,
           (select count(*) from {{ ref('snoco__companies') }}) as actual
    union all
    select 'companies unique on company_id', 0,
           (select count(*) - count(distinct company_id) from {{ ref('snoco__companies') }})
    union all
    -- C6 is named "Inc.", which is legal form and nothing else. It must
    -- normalise away entirely or it becomes a match magnet.
    select 'name that is only a legal form normalises to null', 1,
           (select count(*) from {{ ref('snoco__companies') }}
            where company_id = 'C6' and company_name_normalized is null)
    union all
    -- C5 has two lei values; the later observed one must win deterministically.
    select 'EAV pivot picks the most recently observed value', 1,
           (select count(*) from {{ ref('snoco__companies') }}
            where company_id = 'C5' and cik = '0000000005')
    union all
    -- C7 carries 30 LEIs, over the guard of 25, so none of them may appear.
    select 'oversized lei array is withheld', 0,
           (select count(*) from {{ ref('snoco__company_identifiers') }}
            where company_id = 'C7' and identifier_type = 'lei')
    union all
    -- C5's two LEIs are under the guard and must both survive.
    select 'in-guard lei array is flattened', 2,
           (select count(*) from {{ ref('snoco__company_identifiers') }}
            where company_id = 'C5' and identifier_type = 'lei')
    union all
    -- The uppercase, schemed, pathed domain on C4 must reduce to a bare host.
    select 'uppercase domain with scheme and path is normalised', 1,
           (select count(*) from {{ ref('snoco__company_domains') }}
            where company_id = 'C4' and domain = 'aurorarobotics.mx')
    union all
    select 'shared domain is flagged', 2,
           (select count(*) from {{ ref('snoco__company_domains') }}
            where domain = 'shared-registrar.com' and is_shared_domain)
    union all
    -- C4 has two parents, so it appears on two paths and company_id is not unique.
    select 'multi-parent company appears once per path', 2,
           (select count(*) from {{ ref('snoco__company_hierarchy') }}
            where company_id = 'C4')
    union all
    select 'multi-parent company is flagged', 1,
           (select count(distinct company_id) from {{ ref('snoco__company_hierarchy') }}
            where has_multiple_parents)
    union all
    select 'hierarchy surrogate key is unique', 0,
           (select count(*) - count(distinct company_hierarchy_sk)
            from {{ ref('snoco__company_hierarchy') }})
    union all
    -- Orphan filers have no company_id and must survive in staging.
    select 'sec filers with no company are preserved in staging', 2,
           (select count(*) from {{ ref('stg_snoco__sec_filers') }} where company_id is null)
    union all
    select 'sec filer staging is unique on cik', 0,
           (select count(*) - count(distinct cik) from {{ ref('stg_snoco__sec_filers') }})
    union all
    -- BBG000UNKNOWN is referenced but not described, so it must not resolve.
    select 'unresolvable security is marked unresolved', 1,
           (select count(*) from {{ ref('snoco__company_securities') }}
            where security_id = 'BBG000UNKNOWN' and not is_resolved)
    union all
    select 'resolvable security carries reference attributes', 1,
           (select count(*) from {{ ref('snoco__company_securities') }}
            where security_id = 'BBG000FAKE001' and is_resolved and asset_class = 'Equity')
    union all
    select 'country resolves to an ISO code via geography', 1,
           (select count(*) from {{ ref('snoco__companies') }}
            where company_id = 'C1' and country_iso_alpha2 = 'US')
    union all
    -- C1's SEC country is the EDGAR code X1; EAV leaks ISO US. SEC must win,
    -- and state must resolve through geography rather than the raw code.
    select 'sec edgar country wins over eav iso leak', 1,
           (select count(*) from {{ ref('snoco__companies') }}
            where company_id = 'C1'
              and edgar_country_code = 'X1'
              and edgar_country_name = 'United States'
              and edgar_state_code = 'TX'
              and edgar_state_name = 'Texas'
              and country_iso_alpha3 = 'USA'
              and country_name = 'United States'
              and state_iso_3166_2 = 'US-TX'
              and state_name = 'Texas')
    union all
    -- C5's SEC country and state are empty strings. coalesce used to prefer
    -- those blanks over the EAV values X1 / NY.
    select 'empty sec country falls through to eav', 1,
           (select count(*) from {{ ref('snoco__companies') }}
            where company_id = 'C5'
              and edgar_country_code = 'X1'
              and edgar_state_code = 'NY'
              and country_iso_alpha2 = 'US'
              and state_iso_3166_2 = 'US-NY')
    union all
    -- C8's SEC country is xx, the EDGAR unknown placeholder, and there is no
    -- EAV country. The code must be NULL; geography still resolves.
    select 'xx placeholder is nulled but geography still resolves', 1,
           (select count(*) from {{ ref('snoco__companies') }}
            where company_id = 'C8'
              and edgar_country_code is null
              and edgar_country_name is null
              and country_iso_alpha2 = 'US'
              and state_iso_3166_2 = 'US-CO')
    union all
    -- C2 is not an SEC filer. EAV-only EDGAR X0 (United Kingdom) is kept, and
    -- there is no geo_id so there is no ISO code to invent.
    select 'eav-only edgar country is kept without an iso code', 1,
           (select count(*) from {{ ref('snoco__companies') }}
            where company_id = 'C2'
              and edgar_country_code = 'X0'
              and edgar_country_name = 'United Kingdom'
              and country_iso_alpha2 is null)
    union all
    select 'no empty-string country or state codes', 0,
           (select count(*) from {{ ref('snoco__companies') }}
            where edgar_country_code = '' or edgar_state_code = '')

)

select assertion, expected, actual
from expectations
where actual is distinct from expected

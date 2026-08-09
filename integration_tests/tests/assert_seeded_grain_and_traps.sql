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

)

select assertion, expected, actual
from expectations
where actual is distinct from expected

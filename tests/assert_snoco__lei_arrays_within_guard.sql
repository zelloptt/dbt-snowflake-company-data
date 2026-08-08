{{ config(
    enabled = var('snoco_company_enabled', true),
    severity = 'warn',
    warn_if = '>0'
) }}

-- Reports companies whose LEI array exceeds snoco__max_identifier_array_size
-- and was therefore withheld from snoco__company_identifiers.
--
-- WARN, not ERROR, and deliberately so. These rows are a defect in the provider
-- data that we cannot fix and would be wrong to fail a build over. What we do
-- want is for the number to be visible on every run, because the guard is
-- silent by construction: if the provider fixes the bug, or makes it worse, the
-- only signal is this count changing.
--
-- Measured 2026-08-08: 230 companies over the cap of 25, largest array 5,287
-- elements shared verbatim by 47 companies, 224 of the 230 with a slash in the
-- name. Suppresses 270,001 false company-to-LEI rows. See docs/DISCOVERY.md
-- trap 1.

select
    company_id,
    company_name,
    array_size(lei_array) as lei_array_size

from {{ ref('stg_snoco__company_index') }}
where lei_array is not null
  and array_size(lei_array) > {{ var('snoco__max_identifier_array_size', 25) }}

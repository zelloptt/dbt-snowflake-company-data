{{ config(
    enabled = var('snoco_company_enabled', true),
    severity = 'warn',
    warn_if = '>0'
) }}

{%- set baseline = var('snoco__expected_oversized_lei_arrays', 0) -%}
{%- set tolerance = var('snoco__oversized_lei_array_tolerance', 50) -%}

-- Fires when the number of companies whose LEI array exceeds
-- snoco__max_identifier_array_size DRIFTS from the known baseline, not merely
-- when any exist.
--
-- The previous version of this test warned on any row, and the share then
-- returned about 230. Every consumer therefore got a permanent warning on every
-- build for a provider defect they cannot fix, and anyone running --warn-error
-- got a hard failure. A test that always fires is a test everyone learns to
-- ignore, which is worse than not having one.
--
-- So the baseline is a var. While the provider's grouping bug was live it was
-- 230. Snowflake fixed the bug upstream in 2026-11 (0 oversized arrays,
-- measured 2026-11-11), so the default is now 0 and the test speaks up only if
-- oversized arrays come back, by more than snoco__oversized_lei_array_tolerance.
--
-- Consumers reading an older vintage of the share, or a filtered replica,
-- should set snoco__expected_oversized_lei_arrays to whatever their own count
-- is. Set the tolerance to 0 as well to warn on the first oversized array.
--
-- Still WARN rather than ERROR: this is provider data we do not control, and
-- drift is a signal to go and look, not a reason to fail someone's build.

with affected as (

    select count(*) as oversized_array_count
    from {{ ref('stg_snoco__company_index') }}
    where lei_array is not null
      and array_size(lei_array) > {{ var('snoco__max_identifier_array_size', 25) }}

)

select
    oversized_array_count,
    {{ baseline }} as expected_count,
    {{ tolerance }} as tolerance,
    case
        when oversized_array_count > {{ baseline + tolerance }}
            then 'Oversized LEI arrays INCREASED beyond tolerance. More companies now carry a shared identifier array; check docs/DISCOVERY.md trap 1 and consider whether the guard still fits.'
        else 'Oversized LEI arrays DECREASED beyond tolerance. Your baseline is above what the share now carries; the provider fixed its grouping bug in 2026-11, so set snoco__expected_oversized_lei_arrays to your current count (0 on the share).'
    end as drift_direction

from affected
where oversized_array_count > {{ baseline + tolerance }}
   or oversized_array_count < {{ baseline - tolerance if baseline > tolerance else 0 }}

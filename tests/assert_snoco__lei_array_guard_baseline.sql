{{ config(
    enabled = var('snoco_company_enabled', true),
    severity = 'warn',
    warn_if = '>0'
) }}

{%- set baseline = var('snoco__expected_oversized_lei_arrays', 230) -%}
{%- set tolerance = var('snoco__oversized_lei_array_tolerance', 50) -%}

-- Fires when the number of companies whose LEI array exceeds
-- snoco__max_identifier_array_size DRIFTS from the known baseline, not merely
-- when any exist.
--
-- The previous version of this test warned on any row, and the share always
-- returns about 230. Every consumer therefore got a permanent warning on every
-- build for a provider defect they cannot fix, and anyone running --warn-error
-- got a hard failure. A test that always fires is a test everyone learns to
-- ignore, which is worse than not having one.
--
-- So the baseline is a var. The test passes while the count sits near 230 and
-- speaks up if the provider fixes the bug (count drops) or makes it worse
-- (count climbs), which are the only two things worth knowing.
--
-- Consumers reading a different vintage of the share, or a filtered replica,
-- should set snoco__expected_oversized_lei_arrays to whatever their own count
-- is. Setting it to 0 turns this back into "warn if any exist".
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
        else 'Oversized LEI arrays DECREASED beyond tolerance. The provider may have fixed the grouping bug, in which case snoco__max_identifier_array_size can be raised or removed.'
    end as drift_direction

from affected
where oversized_array_count > {{ baseline + tolerance }}
   or oversized_array_count < {{ baseline - tolerance if baseline > tolerance else 0 }}

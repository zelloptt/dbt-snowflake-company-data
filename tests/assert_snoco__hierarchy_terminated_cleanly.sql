{{ config(enabled = var('snoco_company_enabled', true)) }}

-- Fails if any node sits at snoco__hierarchy_max_depth.
--
-- The recursive CTE stops at that depth. A node sitting exactly on it means the
-- walk was cut short rather than finishing, so the hierarchy is silently
-- truncated and root_company_id is wrong for everything below the cut. There is
-- no other symptom: the model builds, the counts look plausible, and the
-- lineage is quietly incomplete.
--
-- Real depth on the free share is a handful of levels against a limit of 10, so
-- this firing means either the provider started publishing real hierarchies or
-- somebody lowered the var without checking.

select
    company_id,
    root_company_id,
    depth,
    hierarchy_path

from {{ ref('snoco__company_hierarchy') }}
where depth >= {{ var('snoco__hierarchy_max_depth', 10) }}

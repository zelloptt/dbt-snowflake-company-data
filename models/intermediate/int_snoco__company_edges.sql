{{ config(enabled = var('snoco_company_enabled', true)) }}

-- One row per parent/child edge, deduplicated to a single direction.
--
-- The share stores every relationship twice. Verified: all 424 'Parent' rows
-- have a matching 'Subsidiary' row with the endpoints swapped, so the 848 rows
-- describe 424 edges.
--
-- Direction was established from the data rather than assumed. On a 'Parent'
-- row, company_id is the parent and related_company_id is the child; the
-- mirrored 'Subsidiary' row reads (child, parent). Taking one relationship_type
-- and dropping the other is therefore lossless.

select
    company_id          as parent_company_id,
    related_company_id  as child_company_id,
    observed_from_date

from {{ ref('stg_snoco__company_relationships') }}
where relationship_type = 'Parent'

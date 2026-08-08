{{ config(enabled = var('snoco_company_enabled', true)) }}

{%- set max_depth = var('snoco__hierarchy_max_depth', 10) -%}

-- Each record represents one company's position on one path through a corporate
-- hierarchy.
--
-- Grain: one row per distinct root-to-company path, keyed by
-- company_hierarchy_sk. NOT one row per company, and that is a property of the
-- data rather than a modelling choice: **21 companies have more than one
-- parent**, so the structure is a directed acyclic graph, not a tree. Those
-- companies appear once per path, 713 rows covering 683 distinct companies.
--
-- If you need one row per company, decide which parent wins and say so
-- explicitly. Do not assume company_id is unique here; it is not, and
-- parent_count is provided so the multi-parent rows are easy to find.
--
-- Companies with no relationships at all are absent; join from
-- snoco__companies if you need the full spine.
--
-- SET EXPECTATIONS BEFORE YOU BUILD ON THIS. The free share carries 424
-- distinct parent/child edges against a 2,918,929-company spine, which is
-- coverage of roughly 0.015%. The model is correct and it is nearly empty.
-- snoco__hierarchy_max_depth exists for safety, not because real chains
-- approach it.
--
-- Two guards on the recursion. Depth is capped at snoco__hierarchy_max_depth,
-- and a node already present in its own path is not re-expanded. Nothing in the
-- source prevents a cycle, and a cycle in a recursive CTE does not error, it
-- runs until the warehouse gives up.

with edges as (

    select * from {{ ref('int_snoco__company_edges') }}

),

roots as (

    -- a parent that is nobody's child
    select distinct parent_company_id as company_id
    from edges
    where parent_company_id not in (select child_company_id from edges)

),

tree as (

    select
        company_id,
        cast(null as {{ dbt.type_string() }})  as parent_company_id,
        company_id                             as root_company_id,
        0                                      as depth,
        company_id                             as hierarchy_path
    from roots

    union all

    select
        edges.child_company_id,
        edges.parent_company_id,
        tree.root_company_id,
        tree.depth + 1,
        tree.hierarchy_path || ' > ' || edges.child_company_id
    from tree
    inner join edges
        on edges.parent_company_id = tree.company_id
    where tree.depth < {{ max_depth }}
      and not contains(tree.hierarchy_path, edges.child_company_id)

),

parent_counts as (

    select
        child_company_id as company_id,
        count(distinct parent_company_id) as parent_count
    from edges
    group by child_company_id

)

select
    -- hierarchy_path is the natural key: it encodes the full ancestry, so two
    -- rows for the same company under different parents differ here and only
    -- here. Hashing it rather than the column list keeps the key stable if a
    -- descriptive column is added later.
    {{ dbt.hash('tree.hierarchy_path') }} as company_hierarchy_sk,
    tree.company_id,
    tree.parent_company_id,
    tree.root_company_id,
    tree.depth,
    tree.hierarchy_path,
    tree.depth = 0                          as is_ultimate_parent,
    coalesce(parent_counts.parent_count, 0)  as parent_count,
    coalesce(parent_counts.parent_count, 0) > 1 as has_multiple_parents
from tree
left join parent_counts
    on tree.company_id = parent_counts.company_id

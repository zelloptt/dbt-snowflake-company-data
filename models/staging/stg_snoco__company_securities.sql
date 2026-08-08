{{ config(enabled = var('snoco_securities_enabled', true)) }}

-- Company to issued security, 985,971 rows.
--
-- security_id is type-qualified: the same column holds an OpenFIGI FIGI, an
-- OpenFIGI composite id, an OpenFIGI share class id, a PermID quote id or a
-- PermID security id, and which one it is depends on security_id_type. Four of
-- the five resolve against ARRAY columns on the security indexes, so the join
-- is ARRAY_CONTAINS rather than equality. dbt's built-in relationships test
-- cannot express that, which is why tests/ carries a singular test instead.

select
    cast(company_id       as {{ dbt.type_string() }}) as company_id,
    cast(security_id_type as {{ dbt.type_string() }}) as security_id_type,
    cast(security_id      as {{ dbt.type_string() }}) as security_id,
    cast(security_name    as {{ dbt.type_string() }}) as security_name

from {{ source('snoco', 'company_security_relationships') }}
where company_id is not null
  and security_id is not null

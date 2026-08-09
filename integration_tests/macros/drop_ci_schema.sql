{% macro drop_ci_schema() %}
{#-
    Drop the schema this CI run built. Each run targets snoco_ci_<run_id>, so
    without this the account accumulates one schema per pull request push.

    Integration-test project only. It is not part of the package and never
    ships: dbt_packages/ only ever receives the archive, which excludes
    integration_tests/ entirely.
-#}
    {% set sql %}
        drop schema if exists {{ target.database }}.{{ target.schema }} cascade
    {% endset %}
    {% do run_query(sql) %}
    {% do log("dropped " ~ target.database ~ "." ~ target.schema, info=true) %}
{% endmacro %}

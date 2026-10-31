{% macro safe_numeric(column_name) -%}
    (case when {{ column_name }} ~ '^-?[0-9]+(\.[0-9]+)?$' then {{ column_name }}::numeric end)
{%- endmacro %}
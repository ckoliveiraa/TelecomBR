{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set env = target.name -%}

    {%- if 'staging' in node.fqn -%}
        stg_telecom_{{ env }}

    {%- elif 'intermediate' in node.fqn -%}
        int_telecom_{{ env }}

    {%- elif 'marts' in node.fqn -%}
        marts_telecom_{{ env }}

    {%- else -%}
        {{ target.schema }}

    {%- endif -%}

{%- endmacro %}

{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- if 'staging' in node.fqn -%}
        stg_telecom

    {%- elif 'intermediate' in node.fqn -%}
        int_telecom

    {%- elif 'marts' in node.fqn -%}
        marts_telecom

    {%- else -%}
        {{ target.schema }}

    {%- endif -%}

{%- endmacro %}

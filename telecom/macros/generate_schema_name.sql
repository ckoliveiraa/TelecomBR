{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}

    {%- if 'staging' in node.fqn -%}
        stg_telecom

    {%- elif 'intermediate' in node.fqn -%}
        int_telecom

    {%- elif 'marts' in node.fqn -%}
        marts_telecom

    {%- else -%}
        {{ default_schema }}

    {%- endif -%}

{%- endmacro %}
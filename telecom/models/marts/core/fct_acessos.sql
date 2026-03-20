{{
    config(
        materialized='incremental',
        unique_key='acessos_id',
        partition_by={
            'field': 'data_referencia',
            'data_type': 'date',
            'granularity': 'month'
        },
        cluster_by=['sigla_uf', 'grupo_empresa'],
        incremental_strategy='merge'
    )
}}

WITH base AS (
    SELECT * FROM {{ ref('int_acessos_enriquecidos') }}

    {% if is_incremental() %}
        WHERE data_referencia >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH)
    {% endif %}
)

SELECT
    TO_HEX(MD5(CONCAT(
        CAST(ano AS STRING), '|',
        CAST(mes AS STRING), '|',
        COALESCE(sigla_uf, 'NULL'), '|',
        COALESCE(id_municipio, 'NULL'), '|',
        COALESCE(cnpj, 'NULL'), '|',
        COALESCE(tecnologia, 'NULL'), '|',
        COALESCE(transmissao, 'NULL'), '|',
        COALESCE(velocidade, 'NULL'), '|',
        COALESCE(produto, 'NULL')
    ))) AS acessos_id,
    data_referencia,
    ano,
    mes,
    sigla_uf,
    id_municipio,
    cnpj,
    empresa,
    grupo_empresa,
    porte_empresa,
    is_grande_operadora,
    tecnologia,
    transmissao,
    velocidade,
    velocidade_categoria,
    produto,
    acessos
FROM base

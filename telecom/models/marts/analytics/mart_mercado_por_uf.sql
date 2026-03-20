WITH participacao AS (
    SELECT * FROM {{ ref('int_participacao_mercado') }}
),

ranking AS (
    SELECT
        ano,
        mes,
        data_referencia,
        sigla_uf,
        cnpj,
        empresa,
        grupo_empresa,
        porte_empresa,
        is_grande_operadora,
        acessos_empresa,
        total_acessos_uf,
        participacao_mercado_uf,
        RANK() OVER (
            PARTITION BY ano, mes, sigla_uf
            ORDER BY acessos_empresa DESC
        ) AS ranking_uf
    FROM participacao
)

SELECT
    ano,
    mes,
    data_referencia,
    sigla_uf,
    cnpj,
    empresa,
    grupo_empresa,
    porte_empresa,
    is_grande_operadora,
    acessos_empresa,
    total_acessos_uf,
    participacao_mercado_uf,
    ranking_uf,
    ranking_uf <= 3 AS is_top3_uf
FROM ranking

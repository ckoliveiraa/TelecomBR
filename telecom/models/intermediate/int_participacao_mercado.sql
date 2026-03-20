WITH base AS (
    SELECT * FROM {{ ref('int_acessos_enriquecidos') }}
),

total_por_periodo_uf AS (
    SELECT
        ano,
        mes,
        sigla_uf,
        SUM(acessos) AS total_acessos_uf
    FROM base
    GROUP BY
        ano,
        mes,
        sigla_uf
),

acessos_por_empresa_uf AS (
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
        SUM(acessos) AS acessos_empresa
    FROM base
    GROUP BY
        ano,
        mes,
        data_referencia,
        sigla_uf,
        cnpj,
        empresa,
        grupo_empresa,
        porte_empresa,
        is_grande_operadora
)

SELECT
    ae.ano,
    ae.mes,
    ae.data_referencia,
    ae.sigla_uf,
    ae.cnpj,
    ae.empresa,
    ae.grupo_empresa,
    ae.porte_empresa,
    ae.is_grande_operadora,
    ae.acessos_empresa,
    tp.total_acessos_uf,
    SAFE_DIVIDE(ae.acessos_empresa, tp.total_acessos_uf) AS participacao_mercado_uf
FROM acessos_por_empresa_uf AS ae
LEFT JOIN total_por_periodo_uf AS tp
    ON ae.ano = tp.ano
    AND ae.mes = tp.mes
    AND ae.sigla_uf = tp.sigla_uf

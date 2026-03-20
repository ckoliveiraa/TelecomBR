WITH fato AS (
    SELECT * FROM {{ ref('fct_acessos') }}
    WHERE tecnologia IS NOT NULL
),

total_por_periodo AS (
    SELECT
        ano,
        mes,
        SUM(acessos) AS total_acessos_brasil
    FROM fato
    GROUP BY
        ano,
        mes
),

acessos_por_tecnologia AS (
    SELECT
        ano,
        mes,
        data_referencia,
        tecnologia,
        transmissao,
        velocidade_categoria,
        SUM(acessos) AS acessos_tecnologia,
        COUNT(DISTINCT cnpj) AS qtd_empresas_ativas
    FROM fato
    GROUP BY
        ano,
        mes,
        data_referencia,
        tecnologia,
        transmissao,
        velocidade_categoria
)

SELECT
    tec.ano,
    tec.mes,
    tec.data_referencia,
    tec.tecnologia,
    tec.transmissao,
    tec.velocidade_categoria,
    tec.acessos_tecnologia,
    tec.qtd_empresas_ativas,
    tp.total_acessos_brasil,
    SAFE_DIVIDE(tec.acessos_tecnologia, tp.total_acessos_brasil) AS participacao_tecnologia
FROM acessos_por_tecnologia AS tec
LEFT JOIN total_por_periodo AS tp
    ON tec.ano = tp.ano
    AND tec.mes = tp.mes

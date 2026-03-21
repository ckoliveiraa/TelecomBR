-- Retorna linhas quando a soma das participações de mercado por UF/período
-- diverge de 1 (tolerância de 0.001 para arredondamentos de ponto flutuante).
-- Garante que a distribuição de mercado é consistente.

WITH soma_por_uf AS (
    SELECT
        ano,
        mes,
        sigla_uf,
        SUM(participacao_mercado_uf) AS soma_participacao
    FROM {{ ref('mart_mercado_por_uf') }}
    WHERE participacao_mercado_uf IS NOT NULL
    GROUP BY
        ano,
        mes,
        sigla_uf
)

SELECT
    ano,
    mes,
    sigla_uf,
    soma_participacao
FROM soma_por_uf
WHERE ABS(soma_participacao - 1) > 0.001

-- Retorna linhas onde data_referencia não corresponde ao ano e mes da linha.
-- Garante que a construção da data é consistente com os campos de origem.

SELECT
    ano,
    mes,
    data_referencia
FROM {{ ref('int_acessos_enriquecidos') }}
WHERE
    EXTRACT(YEAR FROM data_referencia) != ano
    OR EXTRACT(MONTH FROM data_referencia) != mes

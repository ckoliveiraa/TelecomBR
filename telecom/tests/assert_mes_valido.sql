-- Retorna linhas quando o mês está fora do range válido (1–12).
-- Qualquer resultado indica violação.

SELECT
    mes,
    COUNT(*) AS registros_invalidos
FROM {{ ref('int_acessos_enriquecidos') }}
WHERE mes < 1 OR mes > 12
GROUP BY mes

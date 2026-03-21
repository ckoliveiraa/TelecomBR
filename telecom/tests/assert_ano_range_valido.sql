-- Retorna linhas quando o ano está fora do range histórico válido (2007–2025).
-- Qualquer resultado indica violação.

SELECT
    ano,
    COUNT(*) AS registros_invalidos
FROM {{ ref('int_acessos_enriquecidos') }}
WHERE ano < 2007 OR ano > 2025
GROUP BY ano

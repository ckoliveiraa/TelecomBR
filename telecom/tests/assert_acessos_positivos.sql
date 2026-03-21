-- Retorna linhas quando acessos é zero ou negativo.
-- Contratos devem sempre representar pelo menos 1 acesso ativo.

SELECT
    cnpj,
    empresa,
    sigla_uf,
    data_referencia,
    acessos
FROM {{ ref('fct_acessos') }}
WHERE acessos <= 0

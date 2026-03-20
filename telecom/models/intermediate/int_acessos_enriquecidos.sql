WITH stg AS (
    SELECT * FROM {{ ref('stg_anatel_microdados') }}
),

com_data AS (
    SELECT
        CAST(ano AS INT64) AS ano,
        CAST(mes AS INT64) AS mes,
        SAFE.DATE(CAST(ano AS INT64), CAST(mes AS INT64), 1) AS data_referencia,
        sigla_uf,
        id_municipio,
        cnpj,
        empresa,
        porte_empresa,
        tecnologia,
        transmissao,
        velocidade,
        produto,
        CAST(acessos AS INT64) AS acessos
    FROM stg
),

com_categorias AS (
    SELECT
        ano,
        mes,
        data_referencia,
        sigla_uf,
        id_municipio,
        cnpj,
        empresa,
        porte_empresa,
        tecnologia,
        transmissao,
        velocidade,
        produto,
        acessos,
        CASE
            WHEN velocidade IN ('0Kbps a 512Kbps', '512Kbps a 1Mbps') THEN 'Até 1 Mbps'
            WHEN velocidade IN ('1Mbps a 2Mbps', '2Mbps a 4Mbps', '4Mbps a 8Mbps') THEN '1 a 8 Mbps'
            WHEN velocidade = '8Mbps a 34Mbps' THEN '8 a 34 Mbps'
            WHEN velocidade = '34Mbps a 100Mbps' THEN '34 a 100 Mbps'
            WHEN velocidade LIKE '%100Mbps%' OR velocidade LIKE '%Acima%' THEN 'Acima de 100 Mbps'
            ELSE 'Não Informado'
        END AS velocidade_categoria,
        CASE
            WHEN REGEXP_CONTAINS(UPPER(empresa), r'\bVIVO\b') OR UPPER(empresa) LIKE '%TELEFONICA%' THEN 'Vivo'
            WHEN UPPER(empresa) LIKE '%CLARO%' OR REGEXP_CONTAINS(UPPER(empresa), r'\bNET\b') THEN 'Claro'
            WHEN REGEXP_CONTAINS(UPPER(empresa), r'\bTIM\b') THEN 'TIM'
            WHEN REGEXP_CONTAINS(UPPER(empresa), r'\bOI\b') THEN 'Oi'
            ELSE 'Outras'
        END AS grupo_empresa,
        CASE
            WHEN porte_empresa = 'Grande Porte' THEN TRUE
            ELSE FALSE
        END AS is_grande_operadora
    FROM com_data
)

SELECT * FROM com_categorias

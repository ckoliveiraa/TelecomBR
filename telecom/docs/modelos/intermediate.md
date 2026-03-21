{% docs int_acessos_enriquecidos %}
{% raw %}
# Modelos Intermediários

## Visão Geral

A camada intermediate é onde as regras de negócio do projeto `telecom` residem. Os dois modelos desta camada transformam os dados limpos da staging em estruturas semânticas enriquecidas, prontas para serem consumidas pelos marts. Nenhum desses modelos é exposto diretamente ao usuário final — eles funcionam como blocos de construção reutilizáveis.

Ambos os modelos são materializados como **views** no schema `int_telecom`, garantindo que sempre reflitam o estado atual da staging sem armazenar dados redundantes.

---

## Tabela de Conteúdos

- [int\_acessos\_enriquecidos](#int_acessos_enriquecidos)
  - [Propósito](#propósito)
  - [Transformações](#transformações)
  - [Lógica de Categorização de Velocidade](#lógica-de-categorização-de-velocidade)
  - [Mapeamento de Grupos de Empresa](#mapeamento-de-grupos-de-empresa)
  - [Construção de data\_referencia](#construção-de-data_referencia)
  - [Dicionário de Colunas](#dicionário-de-colunas-int_acessos_enriquecidos)
  - [Testes de Qualidade](#testes-de-qualidade-int_acessos_enriquecidos)
  - [SQL do Modelo](#sql-do-modelo-int_acessos_enriquecidos)
- [int\_participacao\_mercado](#int_participacao_mercado)
  - [Propósito](#propósito-1)
  - [Lógica de Agregação](#lógica-de-agregação)
  - [Cálculo de Participação de Mercado](#cálculo-de-participação-de-mercado)
  - [Dicionário de Colunas](#dicionário-de-colunas-int_participacao_mercado)
  - [Testes de Qualidade](#testes-de-qualidade-int_participacao_mercado)
  - [SQL do Modelo](#sql-do-modelo-int_participacao_mercado)
- [Pontos-Chave](#pontos-chave)

---

## int\_acessos\_enriquecidos

### Propósito

Este modelo é o **hub central da camada intermediate**. Ele recebe os dados limpos da staging e aplica cinco transformações principais: conversão de tipos, construção do campo de data, categorização de velocidade, classificação de grupo de empresa e derivação da flag de grande operadora. Todos os outros modelos downstream — `fct_acessos`, `int_participacao_mercado` e os marts de analytics — dependem diretamente deste modelo.

**Dependência:** `stg_anatel_microdados`

**Schema:** `int_telecom`

**Materialização:** `view`

---

### Transformações

O modelo executa as transformações em dois CTEs sequenciais:

#### CTE `com_data`

Responsável pela **conversão explícita de tipos** e pela **construção do campo de data**:

```sql
CAST(ano AS INT64)       → ano (INT64)
CAST(mes AS INT64)       → mes (INT64)
CAST(acessos AS INT64)   → acessos (INT64)
DATE(ano, mes, 1)        → data_referencia (DATE)
```

Todos os campos numéricos chegam da staging sem tipo garantido e são convertidos para `INT64`. O campo `data_referencia` é sintetizado a partir de `ano` e `mes`, fixando sempre o **dia 1** do mês como convenção.

#### CTE `com_categorias`

Responsável pelo **enriquecimento semântico**: categorização de velocidade, classificação de grupo e derivação da flag `is_grande_operadora`. Os detalhes de cada lógica estão documentados nas subseções abaixo.

---

### Lógica de Categorização de Velocidade

O campo `velocidade` da ANATEL usa uma nomenclatura específica com muitas faixas granulares. Para facilitar análises e visualizações, o modelo mapeia essas faixas em 6 categorias simplificadas via `CASE WHEN`:

| Valores Originais da ANATEL | Categoria Resultante |
|---|---|
| `'0Kbps a 512Kbps'`, `'512Kbps a 1Mbps'` | `'Até 1 Mbps'` |
| `'1Mbps a 2Mbps'`, `'2Mbps a 4Mbps'`, `'4Mbps a 8Mbps'` | `'1 a 8 Mbps'` |
| `'8Mbps a 34Mbps'` | `'8 a 34 Mbps'` |
| `'34Mbps a 100Mbps'` | `'34 a 100 Mbps'` |
| Valores que contêm `'100Mbps'` ou `'Acima'` | `'Acima de 100 Mbps'` |
| Qualquer outro valor (incluindo nulo) | `'Não Informado'` |

```sql
CASE
    WHEN velocidade IN ('0Kbps a 512Kbps', '512Kbps a 1Mbps')
        THEN 'Até 1 Mbps'
    WHEN velocidade IN ('1Mbps a 2Mbps', '2Mbps a 4Mbps', '4Mbps a 8Mbps')
        THEN '1 a 8 Mbps'
    WHEN velocidade = '8Mbps a 34Mbps'
        THEN '8 a 34 Mbps'
    WHEN velocidade = '34Mbps a 100Mbps'
        THEN '34 a 100 Mbps'
    WHEN velocidade LIKE '%100Mbps%' OR velocidade LIKE '%Acima%'
        THEN 'Acima de 100 Mbps'
    ELSE 'Não Informado'
END AS velocidade_categoria
```

> **Decisão de design:** A categoria `'Acima de 100 Mbps'` usa `LIKE` em vez de `IN` porque a ANATEL pode introduzir novas subfaixas acima de 100 Mbps (ex: `'100Mbps a 1Gbps'`, `'Acima de 1Gbps'`) sem quebrar a categorização. O `'Não Informado'` garante que nenhum registro fique sem categoria.

---

### Mapeamento de Grupos de Empresa

O mercado brasileiro de telecomunicações é dominado por quatro grandes grupos. O campo `grupo_empresa` classifica cada empresa nesses grupos usando correspondência parcial no nome (`LIKE` com `UPPER` para case-insensitivity):

| Padrão de Correspondência | Grupo Resultante | Racional |
|---|---|---|
| Nome contém `VIVO` ou `TELEFONICA` | `'Vivo'` | Telefônica opera como Vivo no Brasil |
| Nome contém `CLARO` ou `NET` | `'Claro'` | NET foi adquirida pela Claro/América Móvil |
| Nome contém `TIM` | `'TIM'` | Grupo TIM Italia no Brasil |
| Nome contém `OI` | `'Oi'` | Grupo Oi |
| Nenhum dos anteriores | `'Outras'` | Operadoras regionais e ISPs menores |

```sql
CASE
    WHEN UPPER(empresa) LIKE '%VIVO%'
      OR UPPER(empresa) LIKE '%TELEFONICA%' THEN 'Vivo'
    WHEN UPPER(empresa) LIKE '%CLARO%'
      OR UPPER(empresa) LIKE '%NET%'         THEN 'Claro'
    WHEN UPPER(empresa) LIKE '%TIM%'         THEN 'TIM'
    WHEN UPPER(empresa) LIKE '%OI%'          THEN 'Oi'
    ELSE 'Outras'
END AS grupo_empresa
```

> **Limitação conhecida:** A correspondência por `LIKE` pode gerar falsos positivos em nomes de empresas que coincidam parcialmente (ex: uma empresa chamada "NET Telecom Regional" seria classificada como Claro). Para o contexto regulatório, onde os grandes grupos têm nomes padronizados, esta abordagem é suficientemente precisa.

---

### Construção de data\_referencia

```sql
DATE(CAST(ano AS INT64), CAST(mes AS INT64), 1) AS data_referencia
```

O campo `data_referencia` é uma coluna sintetizada que representa o **primeiro dia do mês de referência**. Não existe na fonte original — é construída a partir de `ano` e `mes`. A convenção de usar o dia 1 é consistente em todo o projeto.

**Por que sintetizar este campo?**
- Permite joins diretos com outras tabelas de série temporal usando tipo `DATE`.
- Viabiliza o particionamento mensal de `fct_acessos` pelo BigQuery.
- Simplifica filtros de janela temporal (ex: `data_referencia >= '2020-01-01'`).
- Habilita funções de data nativas (ex: `DATE_DIFF`, `DATE_TRUNC`).

---

### Dicionário de Colunas — int\_acessos\_enriquecidos

| Coluna | Tipo | Nulável | Origem | Descrição |
|---|---|---|---|---|
| `ano` | INT64 | Não | Staging (cast) | Ano de referência |
| `mes` | INT64 | Não | Staging (cast) | Mês de referência (1–12) |
| `data_referencia` | DATE | Não | Derivada | Primeiro dia do mês de referência |
| `sigla_uf` | STRING | Não | Staging | Sigla da Unidade da Federação |
| `id_municipio` | STRING | Sim | Staging | Código IBGE do município (7 dígitos) |
| `cnpj` | STRING | Não | Staging | CNPJ da empresa prestadora |
| `empresa` | STRING | Sim | Staging | Razão social da empresa |
| `porte_empresa` | STRING | Sim | Staging | Porte da empresa conforme ANATEL |
| `tecnologia` | STRING | Sim | Staging | Tecnologia de acesso |
| `transmissao` | STRING | Sim | Staging | Meio de transmissão |
| `velocidade` | STRING | Sim | Staging | Faixa de velocidade original da ANATEL |
| `produto` | STRING | Sim | Staging | Tipo de produto |
| `acessos` | INT64 | Não | Staging (cast) | Quantidade de contratos ativos |
| `velocidade_categoria` | STRING | Não | Derivada | Categoria simplificada de velocidade (6 valores) |
| `grupo_empresa` | STRING | Não | Derivada | Grupo operacional (Vivo, Claro, TIM, Oi, Outras) |
| `is_grande_operadora` | BOOLEAN | Não | Derivada | TRUE quando `porte_empresa = 'Grande Porte'` |

---

### Testes de Qualidade — int\_acessos\_enriquecidos

| Coluna | Teste | Valores Aceitos / Condição |
|---|---|---|
| `ano` | `not_null` | — |
| `mes` | `not_null` | — |
| `data_referencia` | `not_null` | — |
| `sigla_uf` | `not_null` | — |
| `cnpj` | `not_null` | — |
| `acessos` | `not_null` | — |
| `acessos` | `dbt_utils.expression_is_true` | `>= 0` |
| `velocidade_categoria` | `not_null` | — |
| `velocidade_categoria` | `accepted_values` | Os 6 valores definidos |
| `grupo_empresa` | `not_null` | — |
| `grupo_empresa` | `accepted_values` | `Vivo`, `Claro`, `TIM`, `Oi`, `Outras` |
| `is_grande_operadora` | `not_null` | — |

---

### SQL do Modelo — int\_acessos\_enriquecidos

**Arquivo:** `models/intermediate/int_acessos_enriquecidos.sql`

```sql
WITH stg AS (
    SELECT * FROM {{ ref('stg_anatel_microdados') }}
),

com_data AS (
    SELECT
        CAST(ano AS INT64) AS ano,
        CAST(mes AS INT64) AS mes,
        DATE(CAST(ano AS INT64), CAST(mes AS INT64), 1) AS data_referencia,
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
            WHEN velocidade IN ('0Kbps a 512Kbps', '512Kbps a 1Mbps')
                THEN 'Até 1 Mbps'
            WHEN velocidade IN ('1Mbps a 2Mbps', '2Mbps a 4Mbps', '4Mbps a 8Mbps')
                THEN '1 a 8 Mbps'
            WHEN velocidade = '8Mbps a 34Mbps'
                THEN '8 a 34 Mbps'
            WHEN velocidade = '34Mbps a 100Mbps'
                THEN '34 a 100 Mbps'
            WHEN velocidade LIKE '%100Mbps%' OR velocidade LIKE '%Acima%'
                THEN 'Acima de 100 Mbps'
            ELSE 'Não Informado'
        END AS velocidade_categoria,
        CASE
            WHEN UPPER(empresa) LIKE '%VIVO%'
              OR UPPER(empresa) LIKE '%TELEFONICA%' THEN 'Vivo'
            WHEN UPPER(empresa) LIKE '%CLARO%'
              OR UPPER(empresa) LIKE '%NET%'         THEN 'Claro'
            WHEN UPPER(empresa) LIKE '%TIM%'         THEN 'TIM'
            WHEN UPPER(empresa) LIKE '%OI%'          THEN 'Oi'
            ELSE 'Outras'
        END AS grupo_empresa,
        CASE
            WHEN porte_empresa = 'Grande Porte' THEN TRUE
            ELSE FALSE
        END AS is_grande_operadora
    FROM com_data
)

SELECT * FROM com_categorias
```

---

## int\_participacao\_mercado

### Propósito

Este modelo calcula a **participação de mercado de cada empresa por UF e período**. A granularidade é reduzida em relação ao modelo base: em vez de uma linha por combinação município/tecnologia/velocidade, este modelo agrega tudo em uma linha por `empresa × UF × período`. O resultado é uma visão limpa de competição regional que serve diretamente o mart `mart_mercado_por_uf`.

**Dependência:** `int_acessos_enriquecidos`

**Schema:** `int_telecom`

**Materialização:** `view`

---

### Lógica de Agregação

O modelo usa dois CTEs para calcular o market share:

**CTE `total_por_periodo_uf`**: Agrega o total de acessos de **todas as empresas** em cada combinação `UF × período`.

```sql
SELECT
    ano, mes, sigla_uf,
    SUM(acessos) AS total_acessos_uf
FROM base
GROUP BY ano, mes, sigla_uf
```

**CTE `acessos_por_empresa_uf`**: Agrega os acessos de **cada empresa individualmente** por `UF × período`, preservando atributos descritivos da empresa.

```sql
SELECT
    ano, mes, data_referencia, sigla_uf,
    cnpj, empresa, grupo_empresa, porte_empresa, is_grande_operadora,
    SUM(acessos) AS acessos_empresa
FROM base
GROUP BY
    ano, mes, data_referencia, sigla_uf,
    cnpj, empresa, grupo_empresa, porte_empresa, is_grande_operadora
```

---

### Cálculo de Participação de Mercado

A participação de mercado é calculada no `SELECT` final com `SAFE_DIVIDE`, que retorna `NULL` em vez de erro quando o denominador é zero:

```sql
SAFE_DIVIDE(ae.acessos_empresa, tp.total_acessos_uf) AS participacao_mercado_uf
```

O resultado é um número entre 0 e 1. Por exemplo:
- `0.45` significa que a empresa detém 45% dos acessos da UF no período.
- A soma de `participacao_mercado_uf` de todas as empresas de uma UF em um período deve ser aproximadamente `1.0`.

> O teste customizado `assert_soma_participacao_por_uf` valida que essa soma não diverge de `1.0` por mais de `0.001` (tolerância para arredondamento de ponto flutuante).

O join entre os dois CTEs é feito via `LEFT JOIN` para garantir que empresas com `total_acessos_uf = 0` não sejam descartadas (embora esse cenário seja improvável dado o filtro da staging).

---

### Dicionário de Colunas — int\_participacao\_mercado

| Coluna | Tipo | Nulável | Origem | Descrição |
|---|---|---|---|---|
| `ano` | INT64 | Não | Agregação | Ano de referência |
| `mes` | INT64 | Não | Agregação | Mês de referência |
| `data_referencia` | DATE | Não | Agregação | Primeiro dia do mês de referência |
| `sigla_uf` | STRING | Não | Agregação | Sigla da Unidade da Federação |
| `cnpj` | STRING | Não | Agregação | CNPJ da empresa prestadora |
| `empresa` | STRING | Sim | Agregação | Razão social da empresa |
| `grupo_empresa` | STRING | Sim | Agregação | Grupo operacional (Vivo, Claro, TIM, Oi, Outras) |
| `porte_empresa` | STRING | Sim | Agregação | Porte da empresa |
| `is_grande_operadora` | BOOLEAN | Sim | Agregação | TRUE quando Grande Porte |
| `acessos_empresa` | INT64 | Não | `SUM(acessos)` | Total de acessos da empresa na UF no período |
| `total_acessos_uf` | INT64 | Não | `SUM(acessos)` total UF | Total de acessos de todas as empresas na UF/período |
| `participacao_mercado_uf` | FLOAT64 | Sim | Calculada | Proporção de acessos da empresa na UF (0 a 1) |

---

### Testes de Qualidade — int\_participacao\_mercado

| Coluna | Teste | Condição |
|---|---|---|
| `ano` | `not_null` | — |
| `mes` | `not_null` | — |
| `data_referencia` | `not_null` | — |
| `sigla_uf` | `not_null` | — |
| `cnpj` | `not_null` | — |
| `acessos_empresa` | `not_null` | — |
| `acessos_empresa` | `dbt_utils.expression_is_true` | `> 0` |
| `total_acessos_uf` | `not_null` | — |
| `total_acessos_uf` | `dbt_utils.expression_is_true` | `> 0` |
| `participacao_mercado_uf` | `dbt_utils.expression_is_true` | `BETWEEN 0 AND 1` |

---

### SQL do Modelo — int\_participacao\_mercado

**Arquivo:** `models/intermediate/int_participacao_mercado.sql`

```sql
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
```

---

## Pontos-Chave

- `int_acessos_enriquecidos` é o único modelo que contém toda a lógica de categorização e classificação do projeto. Centralizar aqui garante que qualquer correção na lógica se propague automaticamente para todos os consumidores.
- A construção de `data_referencia` como `DATE(ano, mes, 1)` é a convenção de tempo do projeto inteiro — todos os modelos downstream herdam este campo.
- A categorização de velocidade usa `LIKE` para as faixas acima de 100 Mbps, o que torna o mapeamento resiliente a novas subfaixas que a ANATEL possa introduzir.
- `int_participacao_mercado` usa `SAFE_DIVIDE` para evitar erros de divisão por zero, retornando `NULL` em casos extremos.
- Ambos os modelos são views — não armazenam dados adicionais — mas dependem da staging materializada para ter desempenho aceitável.

{% endraw %}
{% enddocs %}

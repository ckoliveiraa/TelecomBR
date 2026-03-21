{% docs fct_acessos %}
{% raw %}
# Modelos de Marts

## Visão Geral

A camada de marts contém os produtos analíticos finais do projeto `telecom`. São os modelos que analistas de dados, ferramentas de BI e notebooks de análise exploratória consomem diretamente. Todos residem no schema `marts_telecom` no BigQuery e são subdivididos em duas categorias: o mart central (`fct_`) e os marts temáticos de analytics (`mart_`).

---

## Tabela de Conteúdos

- [fct\_acessos](#fct_acessos)
  - [Propósito e Granularidade](#propósito-e-granularidade)
  - [Geração do acessos\_id](#geração-do-acessos_id)
  - [Estratégia Incremental e Janela de Lookback](#estratégia-incremental-e-janela-de-lookback)
  - [Particionamento e Clustering](#particionamento-e-clustering)
  - [Dicionário de Colunas](#dicionário-de-colunas-fct_acessos)
  - [Testes de Qualidade](#testes-de-qualidade-fct_acessos)
  - [SQL do Modelo](#sql-do-modelo-fct_acessos)
- [mart\_evolucao\_tecnologia](#mart_evolucao_tecnologia)
  - [Propósito](#propósito-mart_evolucao_tecnologia)
  - [Lógica de Agregação](#lógica-de-agregação-mart_evolucao_tecnologia)
  - [Dicionário de Colunas](#dicionário-de-colunas-mart_evolucao_tecnologia)
  - [Testes de Qualidade](#testes-de-qualidade-mart_evolucao_tecnologia)
  - [SQL do Modelo](#sql-do-modelo-mart_evolucao_tecnologia)
- [mart\_mercado\_por\_uf](#mart_mercado_por_uf)
  - [Propósito](#propósito-mart_mercado_por_uf)
  - [Lógica de Ranking](#lógica-de-ranking)
  - [Dicionário de Colunas](#dicionário-de-colunas-mart_mercado_por_uf)
  - [Testes de Qualidade](#testes-de-qualidade-mart_mercado_por_uf)
  - [SQL do Modelo](#sql-do-modelo-mart_mercado_por_uf)
- [Pontos-Chave](#pontos-chave)

---

## fct\_acessos

### Propósito e Granularidade

`fct_acessos` é a **tabela fato central do projeto**. Ela contém todos os registros de acessos de banda larga fixa com a granularidade mais atômica disponível na fonte: uma linha por combinação de:

- Período (`ano` + `mes`)
- Município (`id_municipio`)
- Empresa (`cnpj`)
- Tecnologia (`tecnologia` + `transmissao`)
- Faixa de velocidade (`velocidade`)
- Tipo de produto (`produto`)

Esta tabela é o ponto de partida para qualquer análise ad hoc que exija granularidade municipal ou por faixa de velocidade específica. Os marts de analytics (`mart_evolucao_tecnologia` e `mart_mercado_por_uf`) são derivados desta tabela e oferecem visões pré-agregadas.

**Dependência:** `int_acessos_enriquecidos`

**Schema:** `marts_telecom`

**Materialização:** `incremental` (estratégia `merge`)

---

### Geração do acessos\_id

Como a fonte ANATEL não possui chave primária definida, o projeto gera um identificador sintético para cada linha via hash MD5:

```sql
TO_HEX(MD5(CONCAT(
    CAST(ano AS STRING),         '|',
    CAST(mes AS STRING),         '|',
    COALESCE(sigla_uf,    'NULL'), '|',
    COALESCE(id_municipio,'NULL'), '|',
    COALESCE(cnpj,        'NULL'), '|',
    COALESCE(tecnologia,  'NULL'), '|',
    COALESCE(transmissao, 'NULL'), '|',
    COALESCE(velocidade,  'NULL'), '|',
    COALESCE(produto,     'NULL')
))) AS acessos_id
```

**Campos que compõem o hash:**

| Campo | Papel na Identificação |
|---|---|
| `ano` + `mes` | Identifica o período de reporte |
| `sigla_uf` | Localização a nível estadual |
| `id_municipio` | Localização a nível municipal |
| `cnpj` | Identifica a empresa prestadora |
| `tecnologia` | Diferencia o tipo de rede utilizada |
| `transmissao` | Diferencia o meio físico de entrega |
| `velocidade` | Identifica a faixa de velocidade contratada |
| `produto` | Diferencia variantes do produto |

**Separador `|`**: O pipe é usado como delimitador entre campos para evitar colisões de hash (ex: `ano='20'` + `mes='24'` vs. `ano='2024'` + `mes=''`).

**`COALESCE(..., 'NULL')`**: Campos nulos são substituídos pela string `'NULL'` antes da concatenação, pois `MD5(NULL)` retornaria `NULL` em vez de um hash.

> **Atenção:** O `acessos_id` não garante unicidade absoluta — a fonte pode conter registros genuinamente duplicados com todos os campos iguais. O campo serve como chave de controle para o processo de `merge` incremental, não como chave primária de negócio.

---

### Estratégia Incremental e Janela de Lookback

```sql
{{
    config(
        materialized='incremental',
        unique_key='acessos_id',
        incremental_strategy='merge',
        ...
    )
}}

{% if is_incremental() %}
    WHERE data_referencia >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH)
{% endif %}
```

Em execuções incrementais (todas as execuções após a carga inicial completa), o modelo processa apenas os dados dos **últimos 3 meses a partir da data atual**. Esse comportamento é controlado pelo bloco `{% if is_incremental() %}`.

**Por que 3 meses de lookback?**

A ANATEL periodicamente corrige e republica dados históricos recentes. Uma janela de apenas 1 mês poderia perder retificações referentes ao mês anterior. Três meses garante cobertura adequada para absorver essas correções sem reprocessar todo o histórico desde 2007.

**Fluxo de execução do merge:**

```
Para cada linha no resultado incremental (últimos 3 meses):
  ├── Se acessos_id JÁ EXISTE em fct_acessos → UPDATE da linha existente
  └── Se acessos_id NÃO EXISTE em fct_acessos → INSERT de nova linha
```

**Primeira execução (full refresh):** O bloco `{% if is_incremental() %}` não é avaliado e a tabela é construída do zero com todos os dados históricos.

---

### Particionamento e Clustering

**Particionamento mensal por `data_referencia`:**

```yaml
partition_by:
  field: data_referencia
  data_type: date
  granularity: month
```

Cada partição contém os dados de um mês específico. Consultas com filtro de data leem apenas as partições relevantes, reduzindo custo e tempo de execução.

**Clustering por `sigla_uf` e `grupo_empresa`:**

```yaml
cluster_by: ['sigla_uf', 'grupo_empresa']
```

Dentro de cada partição mensal, os dados são ordenados fisicamente por UF e depois por grupo de empresa. Queries que filtram ou agrupam por essas colunas — padrão mais comum nas análises competitivas — se beneficiam de pruning de blocos.

**Exemplo de query otimizada:**

```sql
-- Esta query lê apenas a partição de jan/2024 e
-- só percorre os blocos da UF SP e grupo Vivo
SELECT SUM(acessos)
FROM `projeto.marts_telecom.fct_acessos`
WHERE data_referencia = '2024-01-01'
  AND sigla_uf = 'SP'
  AND grupo_empresa = 'Vivo'
```

---

### Dicionário de Colunas — fct\_acessos

| Coluna | Tipo | Nulável | Descrição |
|---|---|---|---|
| `acessos_id` | STRING | Sim | Hash MD5 identificador da linha (ver seção acima) |
| `data_referencia` | DATE | Não | Primeiro dia do mês de referência (chave de partição) |
| `ano` | INT64 | Não | Ano de referência |
| `mes` | INT64 | Não | Mês de referência |
| `sigla_uf` | STRING | Não | Sigla da Unidade da Federação (chave de clustering) |
| `id_municipio` | STRING | Sim | Código IBGE do município (7 dígitos) |
| `cnpj` | STRING | Não | CNPJ da empresa prestadora |
| `empresa` | STRING | Sim | Razão social da empresa |
| `grupo_empresa` | STRING | Não | Grupo operacional (chave de clustering) |
| `porte_empresa` | STRING | Sim | Porte da empresa conforme ANATEL |
| `is_grande_operadora` | BOOLEAN | Sim | TRUE quando Grande Porte |
| `tecnologia` | STRING | Sim | Tecnologia de acesso (ADSL, VDSL, Fibra Óptica, etc.) |
| `transmissao` | STRING | Sim | Meio de transmissão |
| `velocidade` | STRING | Sim | Faixa de velocidade original da ANATEL |
| `velocidade_categoria` | STRING | Não | Categoria simplificada de velocidade (6 valores) |
| `produto` | STRING | Sim | Tipo de produto |
| `acessos` | INT64 | Não | Quantidade de contratos ativos |

---

### Testes de Qualidade — fct\_acessos

| Coluna | Teste | Condição |
|---|---|---|
| `data_referencia` | `not_null` | — |
| `ano` | `not_null` | — |
| `mes` | `not_null` | — |
| `sigla_uf` | `not_null` | — |
| `cnpj` | `not_null` | — |
| `grupo_empresa` | `not_null` | — |
| `velocidade_categoria` | `not_null` | — |
| `acessos` | `not_null` | — |
| — | `assert_acessos_positivos` (custom) | `acessos > 0` para toda a tabela |

---

### SQL do Modelo — fct\_acessos

**Arquivo:** `models/marts/core/fct_acessos.sql`

```sql
{{
    config(
        materialized='incremental',
        unique_key='acessos_id',
        partition_by={
            'field': 'data_referencia',
            'data_type': 'date',
            'granularity': 'month'
        },
        cluster_by=['sigla_uf', 'grupo_empresa'],
        incremental_strategy='merge'
    )
}}

WITH base AS (
    SELECT * FROM {{ ref('int_acessos_enriquecidos') }}

    {% if is_incremental() %}
        WHERE data_referencia >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH)
    {% endif %}
)

SELECT
    TO_HEX(MD5(CONCAT(
        CAST(ano AS STRING), '|',
        CAST(mes AS STRING), '|',
        COALESCE(sigla_uf,     'NULL'), '|',
        COALESCE(id_municipio, 'NULL'), '|',
        COALESCE(cnpj,         'NULL'), '|',
        COALESCE(tecnologia,   'NULL'), '|',
        COALESCE(transmissao,  'NULL'), '|',
        COALESCE(velocidade,   'NULL'), '|',
        COALESCE(produto,      'NULL')
    ))) AS acessos_id,
    data_referencia,
    ano,
    mes,
    sigla_uf,
    id_municipio,
    cnpj,
    empresa,
    grupo_empresa,
    porte_empresa,
    is_grande_operadora,
    tecnologia,
    transmissao,
    velocidade,
    velocidade_categoria,
    produto,
    acessos
FROM base
```

---

## mart\_evolucao\_tecnologia

### Propósito — mart\_evolucao\_tecnologia

Este mart analítico responde à pergunta: **como a adoção de cada tecnologia de acesso evoluiu ao longo do tempo no Brasil?** Ele agrega os dados da tabela fato por tecnologia, meio de transmissão e categoria de velocidade em nível nacional, calculando a participação percentual de cada tecnologia no total de acessos do país.

Casos de uso diretos:
- Visualizar a curva de crescimento da Fibra Óptica vs. declínio do ADSL.
- Identificar quais tecnologias dominam em qual faixa de velocidade.
- Calcular quantas empresas oferecem cada tecnologia por período.

**Dependência:** `fct_acessos`

**Schema:** `marts_telecom`

**Materialização:** `table`

---

### Lógica de Agregação — mart\_evolucao\_tecnologia

O modelo usa dois CTEs:

**CTE `total_por_periodo`**: Calcula o total nacional de acessos por período (todos os estados, todas as tecnologias).

```sql
SELECT
    ano, mes,
    SUM(acessos) AS total_acessos_brasil
FROM fato
GROUP BY ano, mes
```

**CTE `acessos_por_tecnologia`**: Agrega acessos e conta empresas distintas por combinação de `tecnologia × transmissao × velocidade_categoria × período`.

```sql
SELECT
    ano, mes, data_referencia,
    tecnologia, transmissao, velocidade_categoria,
    SUM(acessos) AS acessos_tecnologia,
    COUNT(DISTINCT cnpj) AS qtd_empresas_ativas
FROM fato
GROUP BY
    ano, mes, data_referencia,
    tecnologia, transmissao, velocidade_categoria
```

> **Filtro de nulos em `tecnologia`**: O CTE inicial aplica `WHERE tecnologia IS NOT NULL` para excluir registros sem tecnologia definida das análises de adoção tecnológica.

A **participação da tecnologia** é calculada como:

```sql
SAFE_DIVIDE(acessos_tecnologia, total_acessos_brasil) AS participacao_tecnologia
```

---

### Dicionário de Colunas — mart\_evolucao\_tecnologia

| Coluna | Tipo | Nulável | Descrição |
|---|---|---|---|
| `ano` | INT64 | Não | Ano de referência |
| `mes` | INT64 | Não | Mês de referência |
| `data_referencia` | DATE | Não | Primeiro dia do mês de referência |
| `tecnologia` | STRING | Não | Tecnologia de acesso (ex: Fibra Óptica, ADSL, VDSL) |
| `transmissao` | STRING | Sim | Meio de transmissão (ex: Cabeada, Satélite) |
| `velocidade_categoria` | STRING | Não | Categoria agrupada de velocidade (6 valores) |
| `acessos_tecnologia` | INT64 | Não | Total de acessos para a combinação tecnologia/velocidade no período |
| `qtd_empresas_ativas` | INT64 | Sim | Quantidade de empresas distintas que oferecem a tecnologia no período |
| `total_acessos_brasil` | INT64 | Não | Total nacional de acessos no período |
| `participacao_tecnologia` | FLOAT64 | Sim | Proporção da tecnologia no total nacional (0 a 1) |

---

### Testes de Qualidade — mart\_evolucao\_tecnologia

| Coluna | Teste | Condição |
|---|---|---|
| `ano` | `not_null` | — |
| `mes` | `not_null` | — |
| `data_referencia` | `not_null` | — |
| `tecnologia` | `not_null` | — |
| `velocidade_categoria` | `not_null` | — |
| `acessos_tecnologia` | `not_null` | — |
| `acessos_tecnologia` | `dbt_utils.expression_is_true` | `> 0` |
| `qtd_empresas_ativas` | `dbt_utils.expression_is_true` | `> 0` |
| `total_acessos_brasil` | `not_null` | — |
| `total_acessos_brasil` | `dbt_utils.expression_is_true` | `> 0` |
| `participacao_tecnologia` | `dbt_utils.expression_is_true` | `BETWEEN 0 AND 1` |

---

### SQL do Modelo — mart\_evolucao\_tecnologia

**Arquivo:** `models/marts/analytics/mart_evolucao_tecnologia.sql`

```sql
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
```

---

## mart\_mercado\_por\_uf

### Propósito — mart\_mercado\_por\_uf

Este mart analítico responde à pergunta: **quem são os líderes de mercado de banda larga em cada estado do Brasil, e como isso evoluiu ao longo do tempo?** Ele consome o modelo intermediário `int_participacao_mercado` e adiciona um ranking de operadoras dentro de cada UF por período, além de uma flag indicando as top 3 empresas de cada estado.

Casos de uso diretos:
- Mapa de concentração de mercado por estado.
- Identificação de monopólios e duopólios regionais.
- Evolução temporal do market share por operadora e UF.
- Filtragem das 3 maiores operadoras de cada estado.

**Dependência:** `int_participacao_mercado`

**Schema:** `marts_telecom`

**Materialização:** `table`

---

### Lógica de Ranking

O ranking é calculado usando a função de janela `RANK()` do BigQuery, particionado por `ano`, `mes` e `sigla_uf`, ordenado pelo total de acessos em ordem decrescente:

```sql
RANK() OVER (
    PARTITION BY ano, mes, sigla_uf
    ORDER BY acessos_empresa DESC
) AS ranking_uf
```

**Por que `RANK()` em vez de `ROW_NUMBER()`?**

`RANK()` atribui o mesmo rank para empresas com exatamente o mesmo número de acessos (empates), deixando uma lacuna no ranking subsequente (ex: 1, 2, 2, 4). `ROW_NUMBER()` quebraria empates arbitrariamente. Para análises competitivas, preservar o empate é semanticamente mais correto.

A flag `is_top3_uf` é derivada diretamente do ranking:

```sql
ranking_uf <= 3 AS is_top3_uf
```

> **Atenção sobre empates e is_top3_uf:** Em casos de empate no ranking 3, mais de 3 empresas podem ter `is_top3_uf = TRUE` em uma mesma UF/período. Isso é comportamento esperado do `RANK()`.

---

### Dicionário de Colunas — mart\_mercado\_por\_uf

| Coluna | Tipo | Nulável | Descrição |
|---|---|---|---|
| `ano` | INT64 | Não | Ano de referência |
| `mes` | INT64 | Não | Mês de referência |
| `data_referencia` | DATE | Não | Primeiro dia do mês de referência |
| `sigla_uf` | STRING | Não | Sigla da Unidade da Federação |
| `cnpj` | STRING | Não | CNPJ da empresa prestadora |
| `empresa` | STRING | Sim | Razão social da empresa |
| `grupo_empresa` | STRING | Sim | Grupo operacional (Vivo, Claro, TIM, Oi, Outras) |
| `porte_empresa` | STRING | Sim | Porte da empresa conforme ANATEL |
| `is_grande_operadora` | BOOLEAN | Sim | TRUE quando Grande Porte |
| `acessos_empresa` | INT64 | Não | Total de acessos da empresa na UF no período |
| `total_acessos_uf` | INT64 | Não | Total de acessos de todas as empresas na UF no período |
| `participacao_mercado_uf` | FLOAT64 | Sim | Proporção de acessos da empresa na UF (0 a 1) |
| `ranking_uf` | INT64 | Não | Posição da empresa no ranking de acessos da UF no período |
| `is_top3_uf` | BOOLEAN | Não | TRUE quando `ranking_uf <= 3` |

---

### Testes de Qualidade — mart\_mercado\_por\_uf

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
| `ranking_uf` | `not_null` | — |
| `ranking_uf` | `dbt_utils.expression_is_true` | `>= 1` |
| `is_top3_uf` | `not_null` | — |
| — | `assert_soma_participacao_por_uf` (custom) | Soma por UF/período `≈ 1.0` (tolerância 0.001) |

---

### SQL do Modelo — mart\_mercado\_por\_uf

**Arquivo:** `models/marts/analytics/mart_mercado_por_uf.sql`

```sql
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
```

---

## Pontos-Chave

- `fct_acessos` é a única tabela incremental do projeto e serve como fonte principal para análises ad hoc que requerem granularidade municipal.
- O `acessos_id` é um identificador sintético via MD5 usado exclusivamente para controle do merge incremental, não como garantia de unicidade de negócio.
- A janela de lookback de 3 meses no incremental de `fct_acessos` absorve retificações tardias da ANATEL sem reprocessar todo o histórico.
- `mart_evolucao_tecnologia` consome `fct_acessos` e é ideal para visualizações de série temporal sobre adoção tecnológica.
- `mart_mercado_por_uf` consome `int_participacao_mercado` (não `fct_acessos` diretamente) para reaproveitar a agregação já calculada na camada intermediate.
- O `RANK()` em `mart_mercado_por_uf` pode resultar em mais de 3 empresas com `is_top3_uf = TRUE` em caso de empate — comportamento esperado e semanticamente correto.

{% endraw %}
{% enddocs %}

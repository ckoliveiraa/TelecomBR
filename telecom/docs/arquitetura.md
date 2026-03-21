{% docs arquitetura %}
{% raw %}
# Arquitetura do Projeto Telecom

## Visão Geral

Este documento descreve a arquitetura técnica completa do projeto `telecom`: as camadas de transformação, as estratégias de materialização adotadas em cada camada, a organização dos schemas no BigQuery, a macro de schema customizado e as decisões de otimização de consulta (particionamento e clustering) da tabela fato.

---

## Tabela de Conteúdos

- [Diagrama do Fluxo de Dados](#diagrama-do-fluxo-de-dados)
- [Camadas de Transformação](#camadas-de-transformação)
- [Schemas no BigQuery](#schemas-no-bigquery)
- [Estratégias de Materialização](#estratégias-de-materialização)
- [Macro de Schema Customizado](#macro-de-schema-customizado)
- [Particionamento e Clustering de fct_acessos](#particionamento-e-clustering-de-fct_acessos)
- [Lógica Incremental](#lógica-incremental)
- [Dependências de Pacotes](#dependências-de-pacotes)
- [Pontos-Chave](#pontos-chave)

---

## Diagrama do Fluxo de Dados

```
basedosdados.br_anatel_banda_larga_fixa.microdados
         |
         v
  [staging]      stg_anatel_microdados         (table  / stg_telecom)
         |
         v
  [intermediate] int_acessos_enriquecidos      (view   / int_telecom)
         |
         +-------> int_participacao_mercado     (view   / int_telecom)
         |                   |
         v                   v
  [marts] fct_acessos        mart_mercado_por_uf     (table / marts_telecom)
         |    (incremental table / marts_telecom)
         v
         mart_evolucao_tecnologia                     (table / marts_telecom)
```

> O diagrama acima representa o grafo acíclico dirigido (DAG) do projeto. Cada seta indica uma dependência declarada via `ref()` ou `source()` no dbt.

---

## Camadas de Transformação

O projeto segue a arquitetura em três camadas proposta pelo dbt, com uma subdivisão da camada de marts:

### Camada 1 — Staging (`stg_`)

Responsável por **acessar a fonte bruta e aplicar as transformações mínimas de limpeza**. Nenhuma lógica de negócio deve residir aqui. A staging:

- Seleciona apenas as colunas necessárias da fonte.
- Aplica `DISTINCT` para remover duplicatas oriundas da fonte pública.
- Filtra registros com `acessos IS NULL`, eliminando linhas sem métrica.
- Mantém os tipos originais das colunas sem coerções complexas.
- Renomeia campos se necessário para padronizar a nomenclatura interna.

**Modelo:** `stg_anatel_microdados`

### Camada 2 — Intermediate (`int_`)

Responsável por aplicar **regras de negócio, enriquecimento semântico e tipagem explícita**. Os modelos intermediários não são expostos diretamente ao consumidor final — eles servem como blocos de construção reutilizáveis pelos marts.

Nesta camada:

- Os tipos de dados são convertidos explicitamente (ex: `CAST(ano AS INT64)`).
- A coluna `data_referencia` é construída a partir de `ano` e `mes`.
- A lógica de categorização de velocidade é aplicada.
- O agrupamento de empresas por grupo operacional é definido.
- Agregações intermediárias (participação de mercado por UF) são calculadas.

**Modelos:** `int_acessos_enriquecidos`, `int_participacao_mercado`

### Camada 3 — Marts (`fct_` e `mart_`)

Responsável por entregar **produtos analíticos finais, otimizados para consumo por ferramentas de BI e analistas**. Divide-se em:

- **Core** (`fct_`): Tabela fato central com granularidade atômica. Materializada de forma incremental para eficiência em grandes volumes.
- **Analytics** (`mart_`): Agregações temáticas pré-calculadas para casos de uso específicos. Materializadas como tabelas completas.

**Modelos:** `fct_acessos`, `mart_evolucao_tecnologia`, `mart_mercado_por_uf`

---

## Schemas no BigQuery

O BigQuery organiza tabelas em datasets (equivalentes a schemas). O projeto utiliza três datasets distintos, um por camada:

| Dataset | Camada | Modelos |
|---|---|---|
| `stg_telecom` | Staging | `stg_anatel_microdados` |
| `int_telecom` | Intermediate | `int_acessos_enriquecidos`, `int_participacao_mercado` |
| `marts_telecom` | Marts (Core + Analytics) | `fct_acessos`, `mart_evolucao_tecnologia`, `mart_mercado_por_uf` |

Essa separação garante controle de acesso granular: analistas de negócio podem receber acesso apenas ao dataset `marts_telecom`, enquanto engenheiros de dados têm acesso a todos os datasets.

> **Nota:** A macro `generate_schema_name` é responsável por mapear os diretórios do projeto para esses schemas. Consulte a seção [Macro de Schema Customizado](#macro-de-schema-customizado) para detalhes.

---

## Estratégias de Materialização

As estratégias foram escolhidas com base no volume de dados, frequência de atualização e padrão de acesso de cada camada.

### Configuração no `dbt_project.yml`

```yaml
models:
  telecom:
    +persist_docs:
      relation: true
      columns: true
    staging:
      +materialized: table
      +schema: staging
    intermediate:
      +materialized: view
      +schema: intermediate
    marts:
      +schema: marts
      core:
        +materialized: table
      analytics:
        +materialized: table
```

### Tabela de Decisões

| Camada | Materialização | Justificativa |
|---|---|---|
| Staging | `table` | A fonte pública é consultada via BigQuery cross-project, o que tem custo por byte lido. Materializar evita reprocessar a fonte a cada execução downstream. |
| Intermediate | `view` | Os modelos intermediários são transformações leves sobre a staging já materializada. Views evitam armazenamento redundante e garantem que os marts sempre leiam dados atualizados. |
| Marts / Core | `incremental` | O volume histórico (2007–presente) é grande. A estratégia incremental reprocessa apenas os últimos 3 meses, reduzindo custo e tempo de execução. |
| Marts / Analytics | `table` | As agregações temáticas são relativamente pequenas e devem estar sempre completas para análises de série histórica. |

---

## Macro de Schema Customizado

Por padrão, o dbt constrói o nome do schema concatenando o schema padrão do perfil com o schema definido no `dbt_project.yml` (ex: `my_project_staging`). Para evitar esse comportamento e controlar com precisão os nomes dos datasets no BigQuery, o projeto utiliza a macro `generate_schema_name`:

**Arquivo:** `macros/generate_schema_name.sql`

```sql
{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}

    {%- if 'staging' in node.fqn -%}
        stg_telecom

    {%- elif 'intermediate' in node.fqn -%}
        int_telecom

    {%- elif 'marts' in node.fqn -%}
        marts_telecom

    {%- else -%}
        {{ default_schema }}

    {%- endif -%}

{%- endmacro %}
```

**Como funciona:** A macro inspeciona o **Fully Qualified Name** (`fqn`) do nó dbt — que inclui o caminho de diretório do modelo — e atribui um nome de dataset fixo com base no diretório. Isso garante que os schemas sejam sempre `stg_telecom`, `int_telecom` e `marts_telecom`, independentemente do schema padrão configurado no perfil dbt.

**Implicação prática:** Mesmo em ambientes de desenvolvimento onde o `target.schema` pode ser `dev_fulano`, os datasets criados serão `stg_telecom`, `int_telecom` e `marts_telecom`. Se for necessário isolar ambientes, é recomendado usar projetos GCP distintos para dev e prod.

---

## Particionamento e Clustering de fct_acessos

A tabela `fct_acessos` é a maior do projeto e recebe configurações especiais de otimização de armazenamento e consulta no BigQuery.

### Particionamento

```yaml
partition_by:
  field: data_referencia
  data_type: date
  granularity: month
```

A tabela é **particionada mensalmente** pelo campo `data_referencia`. Isso significa que o BigQuery armazena os dados de cada mês em uma partição separada. Consultas que filtram por intervalo de datas (ex: `WHERE data_referencia BETWEEN '2023-01-01' AND '2023-12-01'`) leem apenas as partições relevantes, reduzindo drasticamente o volume de bytes processados e o custo.

### Clustering

```yaml
cluster_by: ['sigla_uf', 'grupo_empresa']
```

Dentro de cada partição mensal, os dados são **ordenados fisicamente** por `sigla_uf` e depois por `grupo_empresa`. Consultas que filtram ou agrupam por essas colunas — padrão frequente nas análises de competição regional — se beneficiam do pruning de blocos, reduzindo I/O sem custo adicional.

### Granularidade da Chave de Partição

| Filtro | Partições lidas |
|---|---|
| `data_referencia = '2024-01-01'` | 1 partição (janeiro/2024) |
| `data_referencia BETWEEN '2024-01-01' AND '2024-06-01'` | 6 partições |
| Sem filtro de data | Todas as partições (evitar em produção) |

---

## Lógica Incremental

O modelo `fct_acessos` utiliza a estratégia incremental com `merge` do BigQuery.

### Configuração

```sql
{{
    config(
        materialized='incremental',
        unique_key='acessos_id',
        incremental_strategy='merge',
        partition_by={
            'field': 'data_referencia',
            'data_type': 'date',
            'granularity': 'month'
        },
        cluster_by=['sigla_uf', 'grupo_empresa']
    )
}}
```

### Janela de Lookback — 3 Meses

```sql
{% if is_incremental() %}
    WHERE data_referencia >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH)
{% endif %}
```

Em execuções incrementais (após a primeira carga completa), o modelo reprocessa apenas os dados dos **últimos 3 meses**. Essa janela de lookback foi escolhida porque:

1. A ANATEL frequentemente corrige e republica dados de meses anteriores.
2. Três meses garante que revisões tardias sejam capturadas.
3. O custo de reprocessar 3 meses é significativamente menor que reprocessar todo o histórico.

### Chave de Merge — `acessos_id`

O campo `acessos_id` é um hash MD5 gerado a partir de 9 campos que identificam unicamente um registro de acesso:

```
ano | mes | sigla_uf | id_municipio | cnpj | tecnologia | transmissao | velocidade | produto
```

> **Importante:** A fonte ANATEL não possui chave primária e pode conter duplicatas. O `acessos_id` não garante unicidade absoluta — ele serve como chave de controle para o processo de merge, garantindo que registros já carregados sejam atualizados em vez de inseridos novamente.

### Fluxo do Merge

```
Execução incremental:
  1. Seleciona dados dos últimos 3 meses de int_acessos_enriquecidos
  2. Para cada linha do incremental:
     - Se acessos_id JÁ EXISTE em fct_acessos → UPDATE
     - Se acessos_id NÃO EXISTE em fct_acessos → INSERT
```

---

## Dependências de Pacotes

**Arquivo:** `packages.yml`

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: 1.3.0
```

O projeto depende do pacote `dbt_utils` (versão 1.3.0), mantido pela dbt Labs. Este pacote é utilizado principalmente para:

| Funcionalidade | Uso no Projeto |
|---|---|
| `dbt_utils.expression_is_true` | Testes de validação numérica (ex: `acessos >= 0`, `participacao BETWEEN 0 AND 1`) |

---

## Pontos-Chave

- O projeto segue estritamente a arquitetura em três camadas do dbt: staging, intermediate e marts.
- A macro `generate_schema_name` garante nomes de datasets fixos e previsíveis, independente do ambiente.
- A tabela `fct_acessos` é particionada por mês e clusterizada por UF e grupo de empresa, otimizando consultas regionais e temporais.
- A estratégia incremental com lookback de 3 meses equilibra custo de processamento e completude dos dados, absorvendo retificações tardias da ANATEL.
- A staging é materializada como tabela para evitar custos repetidos de leitura cross-project da Base dos Dados.
- Os modelos intermediários são views, garantindo leveza no armazenamento sem abrir mão da atualidade dos dados.

{% endraw %}
{% enddocs %}

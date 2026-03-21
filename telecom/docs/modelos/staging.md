{% docs stg_anatel_microdados %}
{% raw %}
# Modelo de Staging — stg_anatel_microdados

## Visão Geral

O modelo `stg_anatel_microdados` é o ponto de entrada do pipeline. Ele lê os microdados brutos de banda larga fixa disponibilizados pela ANATEL via Base dos Dados, aplica as transformações mínimas de limpeza e os disponibiliza para as camadas intermediárias. Nenhuma regra de negócio é aplicada nesta camada.

---

## Tabela de Conteúdos

- [Fonte de Dados](#fonte-de-dados)
- [Localização no Projeto](#localização-no-projeto)
- [Transformações Aplicadas](#transformações-aplicadas)
- [Dicionário de Colunas](#dicionário-de-colunas)
- [Testes de Qualidade](#testes-de-qualidade)
- [SQL do Modelo](#sql-do-modelo)
- [Pontos-Chave](#pontos-chave)

---

## Fonte de Dados

| Atributo | Valor |
|---|---|
| Provedor | ANATEL — Agência Nacional de Telecomunicações |
| Plataforma | Base dos Dados (BigQuery público) |
| Projeto GCP | `basedosdados` |
| Dataset | `br_anatel_banda_larga_fixa` |
| Tabela | `microdados` |
| Referência dbt | `{{ source('anatel', 'microdados') }}` |
| Cobertura temporal | 2007 — presente |
| Granularidade | Mês / Município / Empresa / Tecnologia / Velocidade |
| Frequência de atualização | Mensal |

### Sobre a Base dos Dados

A [Base dos Dados](https://basedosdados.org/) é uma organização sem fins lucrativos que padroniza e disponibiliza dados públicos brasileiros via BigQuery. O acesso ao dataset `br_anatel_banda_larga_fixa` é gratuito e não requer credenciais especiais, mas exige que o projeto GCP do usuário seja configurado para fazer billing das queries (os primeiros 1 TB/mês são gratuitos pelo BigQuery).

> **Atenção:** A leitura desta fonte gera custo de processamento no projeto GCP do executor (custo por byte lido cross-project). Por isso, o modelo de staging é materializado como `table`, evitando que cada modelo downstream reprocesse a fonte bruta.

---

## Localização no Projeto

```
telecom/
  models/
    staging/
      stg_anatel_microdados.sql   ← modelo
      schema.yml                  ← descrições e testes
```

**Schema no BigQuery:** `stg_telecom`

**Materialização:** `table`

**Nome completo da tabela:** `<projeto_gcp>.stg_telecom.stg_anatel_microdados`

---

## Transformações Aplicadas

O modelo aplica três transformações sobre os dados brutos:

### 1. Seleção de Colunas

Apenas as colunas relevantes para o pipeline são selecionadas. Colunas internas ou redundantes da fonte são descartadas nesta etapa. As colunas selecionadas são agrupadas semanticamente no SQL por comentários de bloco: `tempo`, `localização`, `empresa`, `produto` e `métricas`.

### 2. Deduplicação com `DISTINCT`

A cláusula `SELECT DISTINCT` é aplicada ao conjunto completo de colunas selecionadas. A fonte pública da ANATEL pode conter registros duplicados decorrentes de processos de republicação ou correção de dados. A deduplicação na staging garante que os modelos downstream não acumulem esse problema.

```sql
select distinct
    ano, mes, sigla_uf, id_municipio,
    cnpj, empresa, porte_empresa,
    tecnologia, transmissao, velocidade, produto,
    acessos
from source
```

### 3. Filtro de Registros sem Métrica

Registros com `acessos IS NULL` são descartados. Um contrato de acesso sem valor de acessos não tem utilidade analítica e pode distorcer agregações. Este é o único filtro de dados aplicado na camada de staging.

```sql
where acessos is not null
```

---

## Dicionário de Colunas

| Coluna | Tipo | Nulável | Descrição |
|---|---|---|---|
| `ano` | INTEGER | Não | Ano de referência do registro (ex: 2024) |
| `mes` | INTEGER | Não | Mês de referência do registro (1 a 12) |
| `sigla_uf` | STRING | Não | Sigla da Unidade da Federação (ex: SP, RJ, MG) |
| `id_municipio` | STRING | Sim | Código IBGE do município com 7 dígitos |
| `cnpj` | STRING | Não | CNPJ da empresa prestadora do serviço |
| `empresa` | STRING | Sim | Razão social da empresa prestadora |
| `porte_empresa` | STRING | Sim | Classificação de porte pela ANATEL (ex: Grande Porte, Pequeno Porte) |
| `tecnologia` | STRING | Sim | Tecnologia de acesso utilizada (ex: ADSL, VDSL, Fibra Óptica, VSAT) |
| `transmissao` | STRING | Sim | Meio de transmissão (ex: Cabeada, Satélite) |
| `velocidade` | STRING | Sim | Faixa de velocidade contratada conforme classificação original da ANATEL |
| `produto` | STRING | Sim | Tipo de produto ofertado (pode ser nulo) |
| `acessos` | INTEGER | Não | Número total de contratos ativos na combinação de atributos |

### Notas sobre Colunas Específicas

**`id_municipio`**: O código IBGE de 7 dígitos é composto pelo código de estado (2 dígitos) + código de município (5 dígitos). Permite join com tabelas de metadados geográficos.

**`velocidade`**: Este campo contém os valores originais da classificação da ANATEL, como `'0Kbps a 512Kbps'`, `'1Mbps a 2Mbps'`, `'Acima de 100Mbps'`. A normalização para categorias simplificadas ocorre no modelo intermediário `int_acessos_enriquecidos`.

**`acessos`**: Representa contratos ativos, não usuários físicos. Um CNPJ pode reportar múltiplas linhas para o mesmo município e período, diferindo em tecnologia, velocidade ou produto.

**`cnpj`**: Identificador único da empresa. Permite rastrear uma operadora ao longo do tempo mesmo que sua razão social mude. É a chave de negócio preferida para análises de empresa.

---

## Testes de Qualidade

Os testes são declarados no arquivo `schema.yml` da pasta staging.

| Coluna | Teste | Descrição |
|---|---|---|
| `ano` | `not_null` | O ano de referência não pode ser nulo |
| `mes` | `not_null` | O mês de referência não pode ser nulo |
| `mes` | `accepted_values` | Deve ser um valor entre 1 e 12 |
| `sigla_uf` | `not_null` | A sigla de UF não pode ser nula |
| `sigla_uf` | `accepted_values` | Deve ser uma das 27 UFs brasileiras válidas |
| `cnpj` | `not_null` | O CNPJ da empresa não pode ser nulo |
| `acessos` | `not_null` | O número de acessos não pode ser nulo (garantido também pelo filtro SQL) |

### Valores Aceitos para `sigla_uf`

```
AC, AL, AM, AP, BA, CE, DF, ES, GO, MA, MG, MS, MT, PA,
PB, PE, PI, PR, RJ, RN, RO, RR, RS, SC, SE, SP, TO
```

---

## SQL do Modelo

**Arquivo:** `models/staging/stg_anatel_microdados.sql`

```sql
with source as (
    select * from {{ source('anatel', 'microdados') }}
),

renamed as (
    select distinct
        -- tempo
        ano,
        mes,

        -- localização
        sigla_uf,
        id_municipio,

        -- empresa
        cnpj,
        empresa,
        porte_empresa,

        -- produto
        tecnologia,
        transmissao,
        velocidade,
        produto,

        -- métricas
        acessos

    from source
)

select * from renamed
where acessos is not null
```

---

## Pontos-Chave

- Este modelo é o único ponto de acesso à fonte bruta da ANATEL em todo o projeto.
- A deduplicação com `DISTINCT` elimina duplicatas antes que elas se propaguem downstream.
- O filtro `acessos IS NOT NULL` é a única regra de negócio desta camada — todas as demais ficam nas camadas intermediária e de marts.
- A materialização como `table` evita o custo repetido de leitura cross-project da Base dos Dados em cada execução.
- Os tipos de dados permanecem como chegam da fonte; a conversão explícita para `INT64` ocorre em `int_acessos_enriquecidos`.

{% endraw %}
{% enddocs %}

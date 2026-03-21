{% docs qualidade_de_dados %}
{% raw %}
# Qualidade de Dados

## Visão Geral

O projeto `telecom` implementa uma estratégia de qualidade de dados em duas camadas: testes genéricos declarados nos arquivos `schema.yml` de cada modelo, e testes customizados escritos como queries SQL na pasta `tests/`. Juntos, esses testes formam um contrato de qualidade que é validado automaticamente a cada execução do pipeline via `dbt test`.

A filosofia adotada é a do **teste como documentação**: cada teste exprime uma expectativa explícita sobre os dados que, ao ser executada, também serve como documentação viva das regras de negócio e restrições do domínio.

---

## Tabela de Conteúdos

- [Como os Testes Funcionam no dbt](#como-os-testes-funcionam-no-dbt)
- [Testes Genéricos por Modelo](#testes-genéricos-por-modelo)
  - [stg\_anatel\_microdados](#stg_anatel_microdados)
  - [int\_acessos\_enriquecidos](#int_acessos_enriquecidos)
  - [int\_participacao\_mercado](#int_participacao_mercado)
  - [fct\_acessos](#fct_acessos)
  - [mart\_evolucao\_tecnologia](#mart_evolucao_tecnologia)
  - [mart\_mercado\_por\_uf](#mart_mercado_por_uf)
- [Testes Customizados (Singular Tests)](#testes-customizados-singular-tests)
  - [assert\_acessos\_positivos](#assert_acessos_positivos)
  - [assert\_ano\_range\_valido](#assert_ano_range_valido)
  - [assert\_data\_referencia\_consistente](#assert_data_referencia_consistente)
  - [assert\_mes\_valido](#assert_mes_valido)
  - [assert\_soma\_participacao\_por\_uf](#assert_soma_participacao_por_uf)
- [Mapa Geral de Cobertura de Testes](#mapa-geral-de-cobertura-de-testes)
- [Pontos-Chave](#pontos-chave)

---

## Como os Testes Funcionam no dbt

No dbt, um teste falha quando a query SQL associada retorna **uma ou mais linhas**. O princípio é: escreva uma query que seleciona os dados violadores — se houver resultado, há problema.

**Testes genéricos** são declarados em arquivos `schema.yml` e executados por macros do dbt core ou de pacotes como `dbt_utils`. São reutilizáveis e parametrizáveis.

**Testes customizados** (também chamados de *singular tests*) são arquivos `.sql` individuais na pasta `tests/`. Cada arquivo contém uma query que retorna linhas quando há violação. São ideais para regras de negócio complexas que não se encaixam nos testes genéricos disponíveis.

Para executar todos os testes:

```bash
dbt test
```

Para executar apenas testes de um modelo específico:

```bash
dbt test --select fct_acessos
```

Para executar apenas os testes customizados:

```bash
dbt test --select test_type:singular
```

---

## Testes Genéricos por Modelo

### stg\_anatel\_microdados

| Coluna | Teste | Descrição |
|---|---|---|
| `ano` | `not_null` | O ano de referência deve sempre estar preenchido |
| `mes` | `not_null` | O mês de referência deve sempre estar preenchido |
| `mes` | `accepted_values` | Deve ser um inteiro de 1 a 12 |
| `sigla_uf` | `not_null` | A UF deve sempre estar identificada |
| `sigla_uf` | `accepted_values` | Deve ser uma das 27 UFs brasileiras reconhecidas |
| `cnpj` | `not_null` | A empresa deve sempre estar identificada pelo CNPJ |
| `acessos` | `not_null` | O número de acessos não pode ser nulo (reforça o filtro SQL) |

**Valores aceitos para `sigla_uf`:**
```
AC, AL, AM, AP, BA, CE, DF, ES, GO, MA, MG, MS, MT, PA,
PB, PE, PI, PR, RJ, RN, RO, RR, RS, SC, SE, SP, TO
```

---

### int\_acessos\_enriquecidos

| Coluna | Teste | Descrição |
|---|---|---|
| `ano` | `not_null` | — |
| `mes` | `not_null` | — |
| `data_referencia` | `not_null` | O campo sintetizado de data deve sempre ser gerado |
| `sigla_uf` | `not_null` | — |
| `cnpj` | `not_null` | — |
| `acessos` | `not_null` | — |
| `acessos` | `dbt_utils.expression_is_true: ">= 0"` | Acessos não podem ser negativos |
| `velocidade_categoria` | `not_null` | Toda linha deve ter uma categoria (incluindo 'Não Informado') |
| `velocidade_categoria` | `accepted_values` | Deve ser um dos 6 valores definidos |
| `grupo_empresa` | `not_null` | Toda empresa deve ser mapeada para um grupo |
| `grupo_empresa` | `accepted_values` | Deve ser Vivo, Claro, TIM, Oi ou Outras |
| `is_grande_operadora` | `not_null` | Flag booleana sempre deve estar definida |

**Valores aceitos para `velocidade_categoria`:**
```
'Até 1 Mbps', '1 a 8 Mbps', '8 a 34 Mbps',
'34 a 100 Mbps', 'Acima de 100 Mbps', 'Não Informado'
```

**Valores aceitos para `grupo_empresa`:**
```
'Vivo', 'Claro', 'TIM', 'Oi', 'Outras'
```

---

### int\_participacao\_mercado

| Coluna | Teste | Descrição |
|---|---|---|
| `ano` | `not_null` | — |
| `mes` | `not_null` | — |
| `data_referencia` | `not_null` | — |
| `sigla_uf` | `not_null` | — |
| `cnpj` | `not_null` | — |
| `acessos_empresa` | `not_null` | — |
| `acessos_empresa` | `dbt_utils.expression_is_true: "> 0"` | Toda empresa na visão de participação deve ter acessos positivos |
| `total_acessos_uf` | `not_null` | — |
| `total_acessos_uf` | `dbt_utils.expression_is_true: "> 0"` | O total da UF deve ser positivo para o cálculo de participação ser válido |
| `participacao_mercado_uf` | `dbt_utils.expression_is_true: "BETWEEN 0 AND 1"` | Participação deve ser uma proporção válida entre 0 e 1 |

---

### fct\_acessos

| Coluna | Teste | Descrição |
|---|---|---|
| `data_referencia` | `not_null` | Chave de partição não pode ser nula |
| `ano` | `not_null` | — |
| `mes` | `not_null` | — |
| `sigla_uf` | `not_null` | — |
| `cnpj` | `not_null` | — |
| `grupo_empresa` | `not_null` | — |
| `velocidade_categoria` | `not_null` | — |
| `acessos` | `not_null` | — |

---

### mart\_evolucao\_tecnologia

| Coluna | Teste | Descrição |
|---|---|---|
| `ano` | `not_null` | — |
| `mes` | `not_null` | — |
| `data_referencia` | `not_null` | — |
| `tecnologia` | `not_null` | Tecnologia não pode ser nula no mart (filtro aplicado no SQL) |
| `velocidade_categoria` | `not_null` | — |
| `acessos_tecnologia` | `not_null` | — |
| `acessos_tecnologia` | `dbt_utils.expression_is_true: "> 0"` | Não faz sentido ter uma combinação tecnologia/velocidade com zero acessos |
| `qtd_empresas_ativas` | `dbt_utils.expression_is_true: "> 0"` | Deve haver pelo menos 1 empresa ativa |
| `total_acessos_brasil` | `not_null` | — |
| `total_acessos_brasil` | `dbt_utils.expression_is_true: "> 0"` | — |
| `participacao_tecnologia` | `dbt_utils.expression_is_true: "BETWEEN 0 AND 1"` | — |

---

### mart\_mercado\_por\_uf

| Coluna | Teste | Descrição |
|---|---|---|
| `ano` | `not_null` | — |
| `mes` | `not_null` | — |
| `data_referencia` | `not_null` | — |
| `sigla_uf` | `not_null` | — |
| `cnpj` | `not_null` | — |
| `acessos_empresa` | `not_null` | — |
| `acessos_empresa` | `dbt_utils.expression_is_true: "> 0"` | — |
| `total_acessos_uf` | `not_null` | — |
| `total_acessos_uf` | `dbt_utils.expression_is_true: "> 0"` | — |
| `participacao_mercado_uf` | `dbt_utils.expression_is_true: "BETWEEN 0 AND 1"` | — |
| `ranking_uf` | `not_null` | — |
| `ranking_uf` | `dbt_utils.expression_is_true: ">= 1"` | Ranking começa em 1 |
| `is_top3_uf` | `not_null` | — |

---

## Testes Customizados (Singular Tests)

Os testes customizados residem na pasta `tests/` do projeto. Cada arquivo é uma query SQL que retorna as **linhas violadoras** — se o resultado for vazio, o teste passa.

---

### assert\_acessos\_positivos

**Arquivo:** `tests/assert_acessos_positivos.sql`

**Modelo testado:** `fct_acessos`

**O que valida:** Garante que não existem registros com `acessos <= 0` na tabela fato. Um contrato de acesso representa pelo menos 1 usuário ativo — valores zero ou negativos indicam problema na fonte ou no pipeline.

**Por que existe se já há um teste `not_null` em `acessos`?**
O teste `not_null` garante apenas que o campo não é `NULL`. Este teste garante que o valor numérico é de fato positivo — uma distinção importante.

```sql
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
```

**O que fazer se falhar:** Investigar se a fonte ANATEL publicou registros com valor zero (possível em arquivos de correção). Avaliar se a regra de negócio deve ser ajustada para aceitar zeros em casos específicos.

---

### assert\_ano\_range\_valido

**Arquivo:** `tests/assert_ano_range_valido.sql`

**Modelo testado:** `int_acessos_enriquecidos`

**O que valida:** Garante que todos os registros têm `ano` dentro do intervalo histórico válido do dataset ANATEL: de 2007 (início da série histórica) a 2025 (limite superior configurado). Anos fora desse range indicam dados corrompidos ou erro de parsing na fonte.

```sql
-- Retorna linhas quando o ano está fora do range histórico válido (2007–2025).
-- Qualquer resultado indica violação.

SELECT
    ano,
    COUNT(*) AS registros_invalidos
FROM {{ ref('int_acessos_enriquecidos') }}
WHERE ano < 2007 OR ano > 2025
GROUP BY ano
```

**O que fazer se falhar:** Verificar se a Base dos Dados publicou dados para um ano além de 2025 (nesse caso, atualizar o limite superior no teste) ou se há registros com `ano` parseado incorretamente (ex: `ano = 207` por truncamento).

> **Nota de manutenção:** O limite superior de 2025 deve ser atualizado periodicamente conforme novos anos de dados são disponibilizados pela ANATEL.

---

### assert\_data\_referencia\_consistente

**Arquivo:** `tests/assert_data_referencia_consistente.sql`

**Modelo testado:** `int_acessos_enriquecidos`

**O que valida:** Garante que o campo `data_referencia` foi construído corretamente a partir de `ano` e `mes`. Especificamente, verifica que o ano extraído de `data_referencia` é igual ao campo `ano`, e que o mês extraído é igual ao campo `mes`. Qualquer inconsistência indicaria um bug na lógica `DATE(ano, mes, 1)`.

```sql
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
```

**O que fazer se falhar:** Este teste não deveria falhar salvo por alteração acidental na lógica de construção de `data_referencia`. Se falhar, revisar o CTE `com_data` em `int_acessos_enriquecidos.sql`.

---

### assert\_mes\_valido

**Arquivo:** `tests/assert_mes_valido.sql`

**Modelo testado:** `int_acessos_enriquecidos`

**O que valida:** Garante que o campo `mes` contém apenas valores entre 1 e 12. O teste na staging valida os valores aceitos no formato de lista — este teste na camada intermediate valida a restrição de intervalo numericamente, funcionando como segunda linha de defesa após a conversão de tipo.

```sql
-- Retorna linhas quando o mês está fora do range válido (1–12).
-- Qualquer resultado indica violação.

SELECT
    mes,
    COUNT(*) AS registros_invalidos
FROM {{ ref('int_acessos_enriquecidos') }}
WHERE mes < 1 OR mes > 12
GROUP BY mes
```

**O que fazer se falhar:** Verificar se a fonte enviou dados com meses inválidos (ex: `mes = 0` ou `mes = 13`). Esses registros devem ser filtrados ou tratados na camada de staging.

---

### assert\_soma\_participacao\_por\_uf

**Arquivo:** `tests/assert_soma_participacao_por_uf.sql`

**Modelo testado:** `mart_mercado_por_uf`

**O que valida:** Garante que a soma das participações de mercado de todas as empresas em uma UF em um período seja aproximadamente igual a `1.0`. Uma soma diferente indica inconsistência na lógica de cálculo de `participacao_mercado_uf`. A tolerância de `0.001` acomoda imprecisões de ponto flutuante em divisões de `FLOAT64`.

Este é o teste mais sofisticado do conjunto — valida uma invariante matemática do domínio de negócio.

```sql
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
```

**O que fazer se falhar:** Investigar se a lógica de `SAFE_DIVIDE` em `int_participacao_mercado` está correta, se há empresas duplicadas sendo somadas, ou se `total_acessos_uf` foi calculado incorretamente. Verificar os valores de `soma_participacao` retornados para identificar o grau de desvio.

---

## Mapa Geral de Cobertura de Testes

A tabela abaixo consolida todos os testes do projeto, indicando onde cada tipo de validação é aplicado.

| Modelo | Testes not_null | Testes accepted_values | Testes expression_is_true | Testes Customizados |
|---|---|---|---|---|
| `stg_anatel_microdados` | 5 colunas | 2 colunas | — | — |
| `int_acessos_enriquecidos` | 8 colunas | 2 colunas | 1 coluna | `assert_ano_range_valido`, `assert_mes_valido`, `assert_data_referencia_consistente` |
| `int_participacao_mercado` | 5 colunas | — | 3 colunas | — |
| `fct_acessos` | 8 colunas | — | — | `assert_acessos_positivos` |
| `mart_evolucao_tecnologia` | 6 colunas | — | 4 colunas | — |
| `mart_mercado_por_uf` | 7 colunas | — | 5 colunas | `assert_soma_participacao_por_uf` |

**Total de testes:** 49 testes genéricos + 5 testes customizados = **54 testes no total**

---

## Pontos-Chave

- Todos os testes seguem a convenção do dbt: uma query que retorna linhas indica falha; resultado vazio indica sucesso.
- Os testes genéricos (`not_null`, `accepted_values`, `expression_is_true`) cobrem restrições de coluna e são declarados nos arquivos `schema.yml`.
- Os cinco testes customizados cobrem invariantes de negócio que não se expressam adequadamente como testes de coluna única: ranges temporais, consistência entre campos derivados e invariantes matemáticas de distribuição de mercado.
- `assert_soma_participacao_por_uf` é o teste mais crítico do projeto — uma falha aqui indica que o cálculo de market share está incorreto.
- `assert_ano_range_valido` requer manutenção periódica para atualizar o limite superior conforme novos anos de dados são disponibilizados.
- A tolerância de `0.001` em `assert_soma_participacao_por_uf` é necessária por limitações de precisão do tipo `FLOAT64` em operações de divisão.

{% endraw %}
{% enddocs %}

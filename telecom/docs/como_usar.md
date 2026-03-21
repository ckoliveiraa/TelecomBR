{% docs como_usar %}
{% raw %}
# Como Usar o Projeto Telecom

## Visão Geral

Este guia prático cobre tudo que é necessário para colocar o projeto `telecom` em execução: pré-requisitos, configuração do ambiente, comandos principais do dbt e orientações sobre como interpretar os marts para análises. Ele é dirigido a engenheiros de dados e analistas que vão operar ou consumir o pipeline.

---

## Tabela de Conteúdos

- [Pré-requisitos](#pré-requisitos)
- [Configuração do Perfil dbt](#configuração-do-perfil-dbt)
- [Instalando Dependências do Projeto](#instalando-dependências-do-projeto)
- [Comandos Principais](#comandos-principais)
  - [dbt run — Executar Modelos](#dbt-run--executar-modelos)
  - [dbt test — Executar Testes](#dbt-test--executar-testes)
  - [dbt docs — Gerar Documentação](#dbt-docs--gerar-documentação)
  - [dbt source freshness — Verificar Atualidade da Fonte](#dbt-source-freshness--verificar-atualidade-da-fonte)
- [Executando Layers Específicas](#executando-layers-específicas)
- [Carga Inicial vs. Execuções Incrementais](#carga-inicial-vs-execuções-incrementais)
- [Como Interpretar os Marts para Análises](#como-interpretar-os-marts-para-análises)
  - [Análises com fct\_acessos](#análises-com-fct_acessos)
  - [Análises com mart\_evolucao\_tecnologia](#análises-com-mart_evolucao_tecnologia)
  - [Análises com mart\_mercado\_por\_uf](#análises-com-mart_mercado_por_uf)
- [Solução de Problemas Comuns](#solução-de-problemas-comuns)
- [Pontos-Chave](#pontos-chave)

---

## Pré-requisitos

Antes de executar o projeto, certifique-se de que os seguintes componentes estão disponíveis:

### Software

| Requisito | Versão Mínima | Como Verificar |
|---|---|---|
| Python | 3.8+ | `python --version` |
| dbt Core | 1.5+ | `dbt --version` |
| dbt-bigquery | compatível com dbt Core | `dbt --version` |
| Google Cloud SDK | qualquer | `gcloud --version` |

### Acesso e Permissões

| Recurso | Permissão Necessária |
|---|---|
| Projeto GCP de destino | `BigQuery Data Editor` + `BigQuery Job User` |
| Dataset `basedosdados.br_anatel_banda_larga_fixa` | Leitura pública (não requer permissão especial, mas requer billing ativo no projeto GCP) |
| Datasets de destino (`stg_telecom`, `int_telecom`, `marts_telecom`) | Criação automática pelo dbt (requer `BigQuery Data Owner` no projeto ou criação prévia pelo admin) |

### Autenticação com o GCP

O dbt se autentica com o BigQuery via Application Default Credentials (ADC). Execute:

```bash
gcloud auth application-default login
```

Ou, para ambientes de serviço (CI/CD), configure a variável de ambiente com a service account:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/caminho/para/service-account.json"
```

---

## Configuração do Perfil dbt

O perfil dbt é configurado no arquivo `~/.dbt/profiles.yml` (fora do repositório do projeto, por questões de segurança). Abaixo está o template de configuração para o projeto `telecom`:

```yaml
telecom:
  target: "{{ env_var('DBT_TARGET', 'prd') }}"
  outputs:
    dev:
      type: bigquery
      method: service-account
      project: telecombr-dev
      dataset: telecom_dev
      keyfile: "{{ env_var('GCP_KEYFILE_DEV', 'credentials/gcp_credentials_dev.json') }}"
      threads: 4
      job_execution_timeout_seconds: 300
      location: US

    prd:
      type: bigquery
      method: service-account
      project: telecombr-prd
      dataset: telecom_prod
      keyfile: "{{ env_var('GCP_KEYFILE_PRD', 'credentials/gcp_credentials_prd.json') }}"
      threads: 4
      job_execution_timeout_seconds: 300
      location: US
```

> **Importante:** O campo `dataset` no perfil é sobrescrito pela macro `generate_schema_name` do projeto. Os dados sempre serão criados nos schemas `stg_telecom`, `int_telecom` e `marts_telecom`, independentemente do valor de `dataset` configurado aqui. O campo ainda é necessário pois o dbt o usa como fallback para outros objetos (ex: snapshots, seeds).

**Verificar a configuração:**

```bash
dbt debug --profiles-dir profiles --project-dir telecom
```

O comando `dbt debug` verifica a conexão com o BigQuery e valida o perfil. Uma saída com `All checks passed!` indica que a configuração está correta.

---

## Instalando Dependências do Projeto

O projeto depende do pacote `dbt_utils`. Após clonar o repositório, instale as dependências:

```bash
dbt deps --profiles-dir profiles --project-dir telecom
```

Este comando lê o arquivo `packages.yml` e baixa o pacote `dbt-labs/dbt_utils==1.3.0` para a pasta `dbt_packages/`. Este passo é necessário apenas uma vez por ambiente (ou quando `packages.yml` for atualizado).

---

## Comandos Principais

### dbt run — Executar Modelos

Executa todos os modelos do projeto e materializa os resultados no BigQuery:

```bash
dbt run
```

**Saída esperada:**
```
Running with dbt=1.x.x
Found 6 models, 49 tests, 1 source...
Concurrency: 4 threads (target='dev')

1 of 6 START sql table model stg_telecom.stg_anatel_microdados .............. [RUN]
1 of 6 OK created sql table model stg_telecom.stg_anatel_microdados ......... [OK in 45.2s]
2 of 6 START sql view model int_telecom.int_acessos_enriquecidos ............. [RUN]
...
```

> **Atenção na primeira execução:** A carga inicial de `fct_acessos` processa todo o histórico desde 2007 e pode levar vários minutos dependendo do volume de dados e dos recursos do projeto GCP.

---

### dbt test — Executar Testes

Executa todos os 54 testes de qualidade de dados (49 genéricos + 5 customizados):

```bash
dbt test
```

Os testes verificam as restrições declaradas nos `schema.yml` e os arquivos SQL customizados em `tests/`. Uma execução bem-sucedida mostra todos os testes como `PASS`.

**Executar testes após um run (recomendado em produção):**

```bash
dbt build  # equivale a dbt run + dbt test para cada modelo, na ordem do DAG
```

---

### dbt docs — Gerar Documentação

Gera a documentação interativa do projeto (portal web com DAG, descrições e schemas):

```bash
# Gerar os artefatos de documentação
dbt docs generate

# Servir a documentação localmente (abre em http://localhost:8080)
dbt docs serve
```

A documentação gerada inclui:
- Visualização interativa do DAG (grafo de dependências).
- Descrições de todos os modelos e colunas (oriundas dos `schema.yml`).
- Estatísticas de testes por modelo.
- Código SQL compilado de cada modelo.

---

### dbt source freshness — Verificar Atualidade da Fonte

Verifica se a fonte de dados da ANATEL foi atualizada recentemente:

```bash
dbt source freshness
```

> **Nota:** Para este comando funcionar, é necessário configurar um bloco `freshness` na definição da source em `schema.yml`. Se não configurado, o comando reportará que a freshness não está definida.

---

## Executando Layers Específicas

O dbt permite selecionar subconjuntos de modelos usando o seletor `--select`. Isso é útil para reprocessar apenas uma camada ou um modelo específico.

### Executar apenas a camada de staging

```bash
dbt run --select staging
```

### Executar apenas a camada intermediate

```bash
dbt run --select intermediate
```

### Executar apenas os marts

```bash
dbt run --select marts
```

### Executar um modelo específico

```bash
dbt run --select fct_acessos
dbt run --select mart_mercado_por_uf
```

### Executar um modelo e todos os seus antecessores (upstream)

O operador `+` antes do nome do modelo inclui todas as dependências:

```bash
# Executa fct_acessos e todos os modelos dos quais ele depende
dbt run --select +fct_acessos
```

### Executar um modelo e todos os seus descendentes (downstream)

O operador `+` depois do nome do modelo inclui todos os modelos que dependem dele:

```bash
# Executa int_acessos_enriquecidos e todos os modelos que o consomem
dbt run --select int_acessos_enriquecidos+
```

### Executar testes apenas para a camada de marts

```bash
dbt test --select marts
```

---

## Carga Inicial vs. Execuções Incrementais

O modelo `fct_acessos` tem comportamento diferente dependendo de como é executado:

### Carga Inicial (Full Refresh)

Na primeira execução, ou quando se deseja reprocessar todo o histórico:

```bash
dbt run --select fct_acessos --full-refresh
```

- Reconstrói a tabela do zero.
- Processa todos os dados desde 2007.
- Mais lento e mais caro em termos de processamento no BigQuery.
- Necessário quando há mudança estrutural no modelo (ex: adição de coluna).

### Execuções Incrementais (Padrão)

Em todas as execuções após a carga inicial:

```bash
dbt run --select fct_acessos
# ou simplesmente
dbt run
```

- Processa apenas os últimos 3 meses de dados.
- Faz merge dos registros: atualiza existentes, insere novos.
- Significativamente mais rápido e barato.
- Captura retificações da ANATEL referentes aos 3 meses anteriores.

> **Quando fazer full refresh de fct_acessos?**
> - Após mudança na lógica de negócio que afete dados históricos (ex: nova categoria de velocidade).
> - Se dados históricos ficarem inconsistentes por algum bug.
> - Periodicamente (ex: trimestral ou semestral) como verificação de integridade.

---

## Como Interpretar os Marts para Análises

### Análises com fct\_acessos

`fct_acessos` é o ponto de partida para análises ad hoc que exigem granularidade municipal ou por faixa de velocidade específica.

**Consulta de exemplo — Total de acessos por estado em um período:**

```sql
SELECT
    sigla_uf,
    SUM(acessos) AS total_acessos
FROM `seu-projeto.marts_telecom.fct_acessos`
WHERE data_referencia = '2024-06-01'
GROUP BY sigla_uf
ORDER BY total_acessos DESC
```

**Consulta de exemplo — Distribuição de velocidades em SP:**

```sql
SELECT
    velocidade_categoria,
    SUM(acessos) AS total_acessos,
    SAFE_DIVIDE(SUM(acessos), SUM(SUM(acessos)) OVER ()) AS participacao
FROM `seu-projeto.marts_telecom.fct_acessos`
WHERE sigla_uf = 'SP'
  AND data_referencia = '2024-06-01'
GROUP BY velocidade_categoria
ORDER BY total_acessos DESC
```

> **Dica de performance:** Sempre filtre por `data_referencia` em queries sobre `fct_acessos` para aproveitar o particionamento mensal e evitar full table scans.

---

### Análises com mart\_evolucao\_tecnologia

`mart_evolucao_tecnologia` é ideal para visualizações de série temporal sobre adoção tecnológica. Os dados já estão agregados em nível nacional.

**Consulta de exemplo — Evolução da participação de Fibra Óptica:**

```sql
SELECT
    data_referencia,
    tecnologia,
    SUM(acessos_tecnologia) AS total_acessos,
    AVG(participacao_tecnologia) AS participacao_media
FROM `seu-projeto.marts_telecom.mart_evolucao_tecnologia`
WHERE tecnologia IN ('Fibra Óptica', 'ADSL')
GROUP BY data_referencia, tecnologia
ORDER BY data_referencia, tecnologia
```

**Consulta de exemplo — Quantas empresas oferecem Fibra em cada período:**

```sql
SELECT
    data_referencia,
    SUM(qtd_empresas_ativas) AS empresas_com_fibra
FROM `seu-projeto.marts_telecom.mart_evolucao_tecnologia`
WHERE tecnologia = 'Fibra Óptica'
GROUP BY data_referencia
ORDER BY data_referencia
```

**Interpretando `participacao_tecnologia`:**

O campo `participacao_tecnologia` é uma proporção entre 0 e 1. Para exibir como percentual, multiplique por 100. A soma de `participacao_tecnologia` por período não totaliza exatamente 1 neste mart porque registros com `tecnologia IS NULL` foram excluídos — use `fct_acessos` para análises que precisam do total absoluto.

---

### Análises com mart\_mercado\_por\_uf

`mart_mercado_por_uf` é o mart mais rico para análises de competição regional.

**Consulta de exemplo — Top 3 operadoras do estado de SP:**

```sql
SELECT
    empresa,
    grupo_empresa,
    acessos_empresa,
    participacao_mercado_uf,
    ranking_uf
FROM `seu-projeto.marts_telecom.mart_mercado_por_uf`
WHERE sigla_uf = 'SP'
  AND data_referencia = '2024-06-01'
  AND is_top3_uf = TRUE
ORDER BY ranking_uf
```

**Consulta de exemplo — Participação dos grupos em todos os estados:**

```sql
SELECT
    sigla_uf,
    grupo_empresa,
    SUM(acessos_empresa) AS total_acessos,
    SUM(participacao_mercado_uf) AS participacao_total
FROM `seu-projeto.marts_telecom.mart_mercado_por_uf`
WHERE data_referencia = '2024-06-01'
GROUP BY sigla_uf, grupo_empresa
ORDER BY sigla_uf, participacao_total DESC
```

**Consulta de exemplo — Evolução do market share da Vivo em MG:**

```sql
SELECT
    data_referencia,
    SUM(acessos_empresa) AS total_acessos_vivo,
    SUM(participacao_mercado_uf) AS participacao_vivo
FROM `seu-projeto.marts_telecom.mart_mercado_por_uf`
WHERE sigla_uf = 'MG'
  AND grupo_empresa = 'Vivo'
GROUP BY data_referencia
ORDER BY data_referencia
```

**Interpretando `ranking_uf`:**

- `ranking_uf = 1` significa que esta empresa tem o maior número de acessos na UF no período.
- Em caso de empate, múltiplas empresas podem ter o mesmo `ranking_uf`.
- `is_top3_uf = TRUE` filtra as 3 maiores (podendo incluir mais de 3 em caso de empate no 3º lugar).

---

## Solução de Problemas Comuns

### Erro: "Access Denied" ao ler a fonte ANATEL

**Causa:** O projeto GCP não tem acesso ao dataset público da Base dos Dados, ou o billing não está ativo.

**Solução:** Verifique se o billing está habilitado no projeto GCP e se o usuário/service account tem permissão `BigQuery Job User` no projeto. O dataset é público — o custo é cobrado no projeto que executa a query.

---

### Erro: "Dataset not found" para stg_telecom / int_telecom / marts_telecom

**Causa:** Os datasets de destino ainda não existem no projeto GCP.

**Solução:** O dbt cria os datasets automaticamente na primeira execução se o usuário tiver a permissão `bigquery.datasets.create`. Se usar uma service account com permissões restritas, peça ao administrador para criar os três datasets antes da primeira execução.

---

### `dbt debug` falha com "Connection refused"

**Causa:** As credenciais do GCP não estão configuradas ou expiraram.

**Solução:**

```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project seu-projeto-gcp-id
```

---

### `dbt run` de fct\_acessos muito lento

**Causa:** Pode ser uma execução de full refresh acidental, ou a janela de lookback de 3 meses está processando um volume muito grande.

**Verificação:** Confirme se a tabela `fct_acessos` já existe no BigQuery. Se não existir, é uma carga inicial (esperado ser lento). Se já existir e o run ainda estiver lento, verifique se a flag `--full-refresh` foi passada inadvertidamente.

---

### Teste `assert_soma_participacao_por_uf` falhando

**Causa:** A soma das participações de uma UF em um período diverge de 1.0 em mais de 0.001.

**Diagnóstico:**

```sql
-- Execute esta query no BigQuery para identificar as UFs problemáticas
SELECT
    ano, mes, sigla_uf,
    SUM(participacao_mercado_uf) AS soma_participacao,
    ABS(SUM(participacao_mercado_uf) - 1) AS desvio
FROM `seu-projeto.marts_telecom.mart_mercado_por_uf`
WHERE participacao_mercado_uf IS NOT NULL
GROUP BY ano, mes, sigla_uf
HAVING ABS(SUM(participacao_mercado_uf) - 1) > 0.001
ORDER BY desvio DESC
```

---

## Pontos-Chave

- Execute `dbt deps` uma vez após clonar o repositório para instalar o pacote `dbt_utils`.
- Use `dbt debug` para verificar a configuração do perfil antes da primeira execução.
- A primeira execução de `fct_acessos` é sempre uma carga completa do histórico — planeje para isso.
- Use `--full-refresh` em `fct_acessos` apenas quando necessário (mudança de lógica ou correção de dados históricos).
- Filtre sempre por `data_referencia` em queries sobre `fct_acessos` para aproveitar o particionamento e controlar custos.
- Use `dbt build` em vez de `dbt run` + `dbt test` separadamente para garantir que os testes são executados na ordem correta do DAG.
- Os marts `mart_evolucao_tecnologia` e `mart_mercado_por_uf` são tabelas pré-agregadas — prefira-os sobre `fct_acessos` para análises que se encaixem no nível de agregação que eles oferecem.

{% endraw %}
{% enddocs %}

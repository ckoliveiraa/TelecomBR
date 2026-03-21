# TelecomBR — Pipeline dbt · Dados ANATEL

Pipeline de dados para análise do mercado de banda larga fixa no Brasil, construído com dbt + BigQuery sobre os microdados públicos da ANATEL disponibilizados via [Base dos Dados](https://basedosdados.org).

---

## Visão geral

```
ANATEL (Base dos Dados)
        │
        ▼
   staging          → padronização e limpeza dos microdados brutos
        │
        ▼
   intermediate     → enriquecimento, categorização e participação de mercado
        │
        ▼
   marts            → tabelas analíticas prontas para consumo
```

---

## Modelos

### Staging
| Modelo | Descrição |
|---|---|
| `stg_anatel_microdados` | Leitura e padronização dos microdados ANATEL. Remove registros nulos e garante tipos consistentes. |

### Intermediate
| Modelo | Descrição |
|---|---|
| `int_acessos_enriquecidos` | Adiciona `data_referencia`, categorias de velocidade e classificação por grupo de operadora (Vivo, Claro, TIM, Oi, Outras). |
| `int_participacao_mercado` | Agrega acessos por empresa/UF/período e calcula share de mercado. |

### Marts
| Modelo | Descrição |
|---|---|
| `fct_acessos` | Fato central de acessos de banda larga fixa por empresa, município e período. |
| `mart_evolucao_tecnologia` | Evolução da distribuição de tecnologias (Fibra, ADSL, VDSL, VSAT, etc.) ao longo do tempo. |
| `mart_mercado_por_uf` | Participação de mercado dos grandes grupos por UF e período, com ranking e share calculado. |

---

## Stack

| Ferramenta | Uso |
|---|---|
| dbt-bigquery 1.11.1 | Transformação e testes |
| BigQuery | Data warehouse |
| Base dos Dados | Fonte dos microdados ANATEL |
| GitHub Actions | CI/CD |
| GitHub Pages | Documentação |

---

## CI/CD

```
push em branch (exceto main)
        │
        ▼
   CI — validar em dev
   dbt build (staging → intermediate → marts)
        │
        ▼ aprovado
   PR aberto automaticamente para main
        │
        ▼ PR mergeado
   CD — pipeline em prd
   dbt build (staging → intermediate → marts)
   dbt docs generate → GitHub Pages
```

- Push direto na `main` é bloqueado
- Cada camada é validada com `dbt build` (run + test por nó)
- Documentação publicada automaticamente após cada deploy

---

## Configuração local

**Pré-requisitos:** Python 3.12, conta GCP.

```bash
# Instalar dependências
pip install -r requirements.txt

# Instalar pacotes dbt
dbt deps --profiles-dir profiles --project-dir telecom

# Rodar em dev
DBT_TARGET=dev dbt build --profiles-dir profiles --project-dir telecom

# Gerar documentação
dbt docs generate --profiles-dir profiles --project-dir telecom
dbt docs serve --profiles-dir profiles --project-dir telecom
```

**Credenciais:** coloque os arquivos de service account em `credentials/` (já ignorado pelo `.gitignore`):
- `credentials/gcp_credentials_dev.json` → projeto `telecombr-dev`
- `credentials/gcp_credentials_prd.json` → projeto `telecombr-prd`

---

## Secrets necessários (GitHub)

| Secret | Descrição |
|---|---|
| `GCP_CREDENTIALS_DEV` | Conteúdo JSON do service account do projeto `telecombr-dev` |
| `GCP_CREDENTIALS_PRD` | Conteúdo JSON do service account do projeto `telecombr-prd` |

---

## Documentação

Publicada automaticamente no GitHub Pages após cada deploy na `main`:

**https://ckoliveiraa.github.io/TelecomBR/**

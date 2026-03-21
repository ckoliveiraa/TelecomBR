{% docs __overview__ %}
{% raw %}
# Projeto dbt — Telecom (ANATEL Banda Larga Fixa)

## Visão Geral

O projeto `telecom` é um pipeline de transformação de dados construído com dbt (data build tool) sobre o BigQuery. Ele ingere os microdados públicos da ANATEL (Agência Nacional de Telecomunicações) referentes a acessos de banda larga fixa no Brasil e os transforma em modelos analíticos prontos para consumo por ferramentas de BI, análise exploratória e relatórios regulatórios.

A fonte de dados é disponibilizada pela Base dos Dados na tabela pública `basedosdados.br_anatel_banda_larga_fixa.microdados`, cobrindo o período de 2007 até o presente, com granularidade mensal por município, empresa, tecnologia e faixa de velocidade.

---

## Contexto de Negócio

O mercado de telecomunicações brasileiro é regulado pela ANATEL, que publica periodicamente os dados de acessos de banda larga fixa de todas as prestadoras autorizadas a operar no país. Esses dados permitem responder perguntas estratégicas e regulatórias como:

- **Distribuição geográfica**: Quais estados e municípios têm maior concentração de acessos?
- **Evolução tecnológica**: Como a adoção de Fibra Óptica substituiu o ADSL ao longo dos anos?
- **Competição de mercado**: Qual é a participação de mercado de cada operadora por UF?
- **Concentração setorial**: O mercado está se tornando mais ou menos concentrado?
- **Análise histórica**: Qual foi a trajetória de crescimento do mercado desde 2007?

O projeto organiza essas respostas em marts analíticos estruturados, evitando que cada time de análise precise reimplementar as mesmas transformações complexas.

---

## Tabela de Conteúdos

- Arquitetura do Projeto (source `anatel`)
- Modelos de Staging (modelo `stg_anatel_microdados`)
- Modelos Intermediários (modelo `int_acessos_enriquecidos`)
- Modelos de Marts (modelo `fct_acessos`)
- Qualidade de Dados (modelo `mart_evolucao_tecnologia`)
- Como Usar (modelo `mart_mercado_por_uf`)

---

## Fluxo de Dados — Visão Rápida

```
Fonte Pública (BigQuery)
  basedosdados.br_anatel_banda_larga_fixa.microdados
         |
         v
  [staging] stg_anatel_microdados          (schema: stg_telecom)
         |
         v
  [intermediate] int_acessos_enriquecidos  (schema: int_telecom)
         |
         +--------> int_participacao_mercado  (schema: int_telecom)
         |
         +--------> fct_acessos              (schema: marts_telecom)
         |
         +--------> mart_evolucao_tecnologia  (schema: marts_telecom)
         |
         +--------> mart_mercado_por_uf       (schema: marts_telecom)
```

---

## Camadas do Projeto

| Camada | Prefixo | Schema | Materialização | Propósito |
|---|---|---|---|---|
| Staging | `stg_` | `stg_telecom` | Table | Limpeza e seleção da fonte bruta |
| Intermediate | `int_` | `int_telecom` | View | Enriquecimento, tipagem e regras de negócio |
| Marts / Core | `fct_` | `marts_telecom` | Incremental Table | Tabela fato central |
| Marts / Analytics | `mart_` | `marts_telecom` | Table | Agregações analíticas para consumo direto |

---

## Casos de Uso Suportados

1. **Distribuição de Serviços**: Visão da cobertura de banda larga por UF e município.
2. **Evolução Tecnológica**: Análise da transição ADSL → Fibra Óptica por período.
3. **Competição por Operadora**: Market share de Vivo, Claro, TIM, Oi e demais por região.
4. **Concentração de Mercado**: Índices de participação e ranking de operadoras por estado.
5. **Análise Histórica**: Séries temporais de 2007 até o período mais recente disponível.

---

## Tecnologias Utilizadas

| Tecnologia | Papel |
|---|---|
| dbt Core | Orquestração das transformações SQL |
| BigQuery | Data warehouse de execução |
| dbt_utils 1.3.0 | Testes genéricos e funções utilitárias |
| Base dos Dados | Fonte pública dos microdados ANATEL |

---

## Como Navegar pela Documentação

Recomenda-se a seguinte ordem de leitura para novos colaboradores:

1. **Este documento** — visão geral do projeto e contexto de negócio.
2. **Arquitetura** (source `anatel`) — entenda as camadas, schemas e decisões técnicas antes de examinar o código.
3. **Staging** (modelo `stg_anatel_microdados`) — ponto de entrada dos dados brutos.
4. **Intermediate** (modelo `int_acessos_enriquecidos`) — onde as regras de negócio são aplicadas.
5. **Marts** (modelo `fct_acessos`) — os produtos analíticos finais do pipeline.
6. **Qualidade de Dados** (modelo `mart_evolucao_tecnologia`) — entenda como a qualidade é garantida.
7. **Como Usar** (modelo `mart_mercado_por_uf`) — guia prático para executar e operar o projeto.

{% endraw %}
{% enddocs %}

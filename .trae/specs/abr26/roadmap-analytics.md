# Roadmap: Observabilidade e Analytics (Event Logger & Heatmap)

Este roadmap organiza as demandas de reestruturação do módulo de Analytics, focando na correção da filtragem, paginação de eventos, diferenciação entre eventos ao vivo vs. acumulados, e a precisão do Heatmap.

Segue as regras de especificação otimizadas para RAG (`spec-rules.md`), dividindo o esforço em Sprints e Tarefas atômicas (0.5 a 2 dias de esforço cada).

---

## 📅 Sprint 1: Infraestrutura de Dados e Filtros (Backend)
**Objetivo:** Garantir que o backend entregue os dados de eventos de forma escalável (paginação) e forneça os metadados necessários para que os filtros funcionem na UI, além de garantir compatibilidade com as métricas legadas.

### 📄 Spec 060.1: Paginação Otimizada de Eventos
- **Tipo:** Backend
- **Esforço estimado:** 1 dia
- **Escopo:**
  - Refatorar o endpoint `Analytics::ListEvents` (ou equivalente) para suportar parâmetros de paginação (`page`, `per_page` ou cursores) de forma eficiente no PostgreSQL.
  - Implementar ordenação correta por data de criação (`created_at DESC`) para garantir a visualização histórica correta.

### 📄 Spec 060.2: Endpoint de Extração de Filtros (Metadados)
- **Tipo:** Backend
- **Esforço estimado:** 0.5 dia
- **Escopo:**
  - Criar um endpoint que agrega e retorna as opções de filtros disponíveis (tipos de evento distintos, usuários/sessões ativas, niches registrados).
  - Garantir que a tela de "Event Logger" tenha os dados necessários para popular os dropdowns de filtragem dinamicamente.

### 📄 Spec 060.3: Manutenção de Compatibilidade da Aba Legada
- **Tipo:** Backend
- **Esforço estimado:** 0.5 dia
- **Escopo:**
  - Investigar e corrigir a rotina que atualizava a aba legada de Analytics, garantindo que o novo modelo de captura continue alimentando as métricas e sumarizações que já existiam, sem quebra de compatibilidade.

---

## 📅 Sprint 2: Explorador de Comportamento (Frontend)
**Objetivo:** Reformular a experiência de visualização de logs, dividindo-a em duas frentes: uma para estudar o histórico de comportamentos e outra para monitorar o tráfego ao vivo.

### 📄 Spec 061.1: Eventos Acumulados com Infinite Scroll e Filtros
- **Tipo:** Frontend
- **Esforço estimado:** 1.5 dias
- **Escopo:**
  - Atualizar o `EventLoggerPage` para consumir o novo endpoint paginado (Spec 060.1) usando a estratégia de Infinite Scroll (ex: via `useInfiniteQuery` do React Query).
  - Implementar os seletores de filtros na UI (conectando na Spec 060.2), permitindo buscar eventos antigos e refinar a busca por tipo, nicho, UTM, ou comportamento.

### 📄 Spec 061.2: Tela de Monitoramento "Live Events"
- **Tipo:** Frontend + Backend
- **Esforço estimado:** 1.5 dias
- **Escopo:**
  - Criar uma aba separada "Live Events" para acompanhar ações acontecendo no site em tempo real.
  - Opcionalmente conectar ao Action Cable (ex: `AnalyticsChannel`) ou usar polling curto focado apenas em eventos dos últimos minutos.

### 📄 Spec 061.3: Enriquecimento da Captura (Estudo de Comportamento)
- **Tipo:** Frontend (AnalyticsProvider)
- **Esforço estimado:** 1 dia
- **Escopo:**
  - Evoluir o que é salvo no payload do evento para não exibir apenas o "elemento HTML clicado". 
  - Adicionar capturas de contexto mais ricas (ex: contexto do formulário, scroll depth max, tempo de permanência), permitindo que o estudo de eventos acumulados tenha mais valor para o analista.

---

## 📅 Sprint 3: Precisão e Escalabilidade do Heatmap
**Objetivo:** Corrigir os problemas de renderização espacial do Heatmap e garantir que ele funcione independentemente da profundidade do scroll ou diferenças de resolução.

### 📄 Spec 062.1: Correção de Coordenadas de Captura (Scroll/Resolução)
- **Tipo:** Frontend (Tracker)
- **Esforço estimado:** 1 dia
- **Escopo:**
  - Atualizar o `useHeatmapTracker.ts` para capturar as coordenadas de clique de forma absoluta em relação ao documento (X, Y reais) somando os offsets de scroll globais.
  - Garantir o armazenamento preciso da viewport para posterior cálculo de proporção.

### 📄 Spec 062.2: Renderização Fluida do Canvas do Heatmap
- **Tipo:** Frontend (HeatmapPage)
- **Esforço estimado:** 1.5 dias
- **Escopo:**
  - Ajustar o canvas em `/admin/metrics` para projetar os pontos de calor usando os dados normatizados, lidando com páginas longas (scroll total) e redimensionando os pontos para a resolução atual do visualizador em relação à captura original.
  - Garantir que áreas profundas da página ainda reflitam os cliques corretamente no heatmap.

---

## PRÓXIMOS PASSOS
Com a aprovação deste Roadmap estrutural, geraremos as **Specs individuais dos itens da Sprint 1 e Sprint 2** como arquivos markdown separados para guiar a implementação. 

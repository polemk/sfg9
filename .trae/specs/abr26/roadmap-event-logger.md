# Roadmap: Event Logger & Analytics Module

Este roadmap organiza a reestruturação da seção de logs e analytics (Event Logger), visando resolver falhas de filtragem, quebras de heatmap e oferecer uma melhor interface de estudo de comportamento histórico e visualização de eventos ao vivo. Os documentos gerados a partir deste roadmap respeitam as regras do `spec-rules.md`.

---

## 📅 Sprint 1: Fundações & Persistência de Logs
**Objetivo:** Consertar a recuperação histórica, inserindo suporte a paginação e scroll infinito no backend, e garantindo que o módulo de analytics antigo não quebre.

### 📄 Spec Log 01: Correção de Paginação, Filtros e Compatibilidade (Backend)
- **Tipo:** Backend
- **Esforço estimado:** 1.5 dias
- **Escopo:**
  - Adaptar o service `Analytics::ListEvents` para suportar `page` / `per_page` (ou cursores se aplicável).
  - Criar endpoints/lógica para devolver dados agregados para os "Filtros" dinâmicos do frontend (recuperar opções existentes de logs).
  - Reparar o fluxo de dados para a "Aba de Analytics Antiga", mantendo a compatibilidade do sistema.

---

## 📅 Sprint 2: Live Monitor vs Study History (UX e Frontend)
**Objetivo:** Dividir a tela de logs entre o consumo em tempo real (websockets) e uma interface de investigação profunda do histórico de eventos paginados, melhorando o payload exibido.

### 📄 Spec Log 02: Interface do Study History e Enriquecimento Visual (Frontend)
- **Tipo:** Frontend
- **Esforço estimado:** 2 dias
- **Escopo:**
  - Separar as responsabilidades de Live Stream e Historical Logs no `EventLoggerPage.tsx`.
  - Integrar a paginação visual com `useInfiniteQuery` e *IntersectionObserver* para propiciar um "scroll infinito" fluído.
  - Substituir a visão superficial ("elemento HTML clicado") por uma interface de jornada do usuário (mostrando parâmetros UTM, tempo de sessão, página anterior, ações do funil).

---

## 📅 Sprint 3: Otimizações Visuais e Heatmap
**Objetivo:** Consertar falhas visuais em painéis auxiliares, garantindo que métricas gráficas consigam ser analisadas adequadamente na plataforma.

### 📄 Spec Log 03: Correção do Limite de Scroll no Heatmap (Frontend)
- **Tipo:** Frontend
- **Esforço estimado:** 0.5 dia
- **Escopo:**
  - Identificar e consertar o bug onde o heatmap em `/admin/metrics` só é renderizado até a metade da tela (bug de scroll/height do wrapper ou cálculo z-index/canvas).
  - Testar a sobreposição em resoluções diferentes para garantir escalabilidade da imagem capturada ou dos dados gerados.

---

## PRÓXIMOS PASSOS
Cada uma das Sprints listadas será detalhada em especificações técnicas atômicas (`spec-log-01-persistence-filters.md`, `spec-log-02-history-ux.md` e `spec-log-03-heatmap.md`), que direcionarão o trabalho em Backend e Frontend.

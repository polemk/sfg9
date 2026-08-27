# Roadmap V4: Operations Knowledge, Assets & Intent Detection
Version: 4.0
Last Updated: March 2026
Focus: Operations as a centralized Knowledge Base (RAG) and Asset Repository, plus AI-driven Intent Detection via semantic search.

---

## 📅 Sprint 1: RAG Foundation, Asset Repository & Intent Detector
*Focus: Setting up pgvector, creating the base models for operations knowledge and media assets, and implementing the semantic search Intent Detection.*

- [ ] **Tarefa 1.1**: Setup pgvector & Database (`spec-016-operations-rag-pgvector.md`)
  - Configurar a extensão `pgvector` no PostgreSQL e preparar a base para busca semântica.
- [ ] **Tarefa 1.2**: OperationKnowledge & OperationAsset Models (`spec-017-operation-knowledge-asset.md`)
  - Criar os modelos para armazenar contexto em texto (RAG) e os ativos de mídia associados a Operation.
- [ ] **Tarefa 1.3**: Background Embeddings Generation (`spec-018-background-embeddings.md`)
  - Implementar jobs (Sidekiq) para vectorizar os textos e descrições das operations assincronamente.
- [ ] **Tarefa 1.4**: Intent Detector Engine (`spec-019-intent-detector.md`)
  - Criar `Operations::IntentDetectorService` e substituir a checagem de keywords por similaridade de cosseno (busca semântica).

## 📅 Sprint 2: Agent Integration & Internal Tools
*Focus: Injecting technical context into prompts and enabling agents to refer to media via shortcodes without payload bloat.*

- [ ] **Tarefa 2.1**: Agent RAG Context Injection (`spec-020-agent-rag-context.md`)
  - Atualizar a integração de IA (`AgentService` etc) para buscar e injetar o texto da `OperationKnowledge` baseada na Operation vinculada ao Lead.
- [ ] **Tarefa 2.2**: Agent Asset Tools (Internal MCP) (`spec-021-agent-asset-tools.md`)
  - Disponibilizar ferramentas internas (Tools) para o Agente consultar/buscar ativos da Operation e usar os "shortcodes" nas respostas.
- [ ] **Tarefa 2.3**: Frontend Asset Shortcode Parser (`spec-022-frontend-asset-parser.md`)
  - No frontend, interceptar shortcodes (ex: `[asset:XYZ123]`) nas mensagens do bote e substituí-los pela renderização da mídia.

## 📅 Sprint 3: Operations Admin UI & Bulk Upload
*Focus: Providing a premium interface for Admins to upload knowledge and manage the showroom experience.*

- [ ] **Tarefa 3.1**: Operations Metrics Backend API (`spec-023-operations-metrics-api.md`)
  - Endpoints administrativos para listar volume de conhecimento, leads e CRUD de Assets/Knowledge.
- [ ] **Tarefa 3.2**: Operations Dashboard UI & Bulk Upload (`spec-024-operations-dashboard-ui.md`)
  - Interface rica em React (`.tsx`) para o painel de operações, permitindo upload em lote e drag-and-drop.

## 📅 Sprint 4: Agent UI Redesign & Embedded Navigation
*Focus: Redesigning the public layout to support a side-by-side persistent agent, and binding specific routes to specific agents.*

- [ ] **Tarefa 4.1**: Route-to-Agent Mapping (Backend & Builder UI) (`spec-025-route-agent-mapping.md`)
  - Adicionar o campo `mapped_routes` (array) ao modelo `ChatFlow`.
  - Atualizar o `AIAgentConfigPanel.tsx` habilitando a seleção de rotas sugeridas do site, permitindo a vinculação de um agente principal para páginas específicas.
- [ ] **Tarefa 4.2**: Side-by-Side Desktop Layout (`spec-026-desktop-split-layout.md`)
  - Refatorar os layouts para acomodar o agente fixo na direita e o conteúdo rolável na esquerda.
  - Ajustar botões como "Saiba mais" para alterar o agente ativo em vez de navegar para outra página, mantendo o contexto.
- [ ] **Tarefa 4.3**: Mobile Responsive Layout & Toggle (`spec-027-mobile-split-layout.md`)
  - Implementar na versão mobile a tela inicial dividida (40% slogan/menu, 60% agente).
  - Configurar o comportamento dinâmico: minimizar o agente automaticamente ao fazer scroll no site, e maximizar o agente ao interagir com o chat.
  - Adicionar um switch no header ("Site Mode / AI Mode") para controle manual.

---

## Documentação de Referência
As especificações detalhadas de cada tarefa encontram-se na pasta `.trae/specs/` seguindo o padrão de nomenclatura `spec-XXX-nome.md`.

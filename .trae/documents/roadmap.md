# Roadmap: AI Agent & Credential Management

**Objetivo:** Permitir a criação e configuração de fluxos do tipo "AI Agent", com gerenciamento seguro de credenciais para modelos de IA (OpenAI, Anthropic, etc.), similar ao n8n.

---

## 📅 Sprint 1: Fundação AI Agent
**Foco:** Estrutura de dados básica e interface de configuração inicial.

- [ ] **Tarefa 004: Estrutura Base do AI Agent** (Atual)
    -   **Contexto:** Diferenciar fluxos "Chatbot" (visual) de "AI Agent" (prompt/model).
    -   **Backend:** Adicionar `kind` e `agent_config` ao modelo `ChatFlow`.
    -   **Frontend:** Modal de seleção de tipo de fluxo e painel de configuração básico (Modelo, Prompt Sistema).

---

## 📅 Sprint 2: Gerenciamento de Credenciais
**Foco:** Armazenamento seguro e gerenciamento de chaves de API.

- [ ] **Tarefa 005: Backend de Credenciais**
    -   **Contexto:** Precisamos armazenar chaves de API com segurança (criptografadas).
    -   **Backend:** Criar modelo `Credential` (nome, tipo, valor_criptografado).
    -   **API:** Endpoints para criar/listar/remover (nunca retornar o valor real, apenas mascarado).

- [ ] **Tarefa 006: UI de Credenciais**
    -   **Contexto:** Interface para o usuário gerenciar suas chaves.
    -   **Frontend:** Nova tela "Credenciais" (ou aba em Configurações). Listagem e formulário de adição.

---

## 📅 Sprint 3: Integração e Configuração Avançada
**Foco:** Conectar as credenciais aos agentes e refinar a configuração.

- [ ] **Tarefa 007: Conectar Agente às Credenciais**
    -   **Contexto:** O agente precisa selecionar qual credencial usar para o modelo escolhido.
    -   **Frontend:** Dropdown de credenciais no `AIAgentConfigPanel`.
    -   **Backend:** Validar uso da credencial na execução do fluxo.

- [ ] **Tarefa 008: Parâmetros Avançados**
    -   **Contexto:** Ajuste fino do modelo.
    -   **Frontend:** Controles para Temperature, Max Tokens, Top P, etc.
    -   **Backend:** Persistência desses parâmetros no `agent_config`.

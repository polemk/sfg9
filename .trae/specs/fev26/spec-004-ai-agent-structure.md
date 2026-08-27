# Tarefa 004: Estrutura Base do AI Agent

**Sprint:** 1 - Fundação AI Agent
**Estimativa:** 1 dia
**Tipo:** Backend + Frontend

---

## Contexto
O sistema atual suporta apenas fluxos visuais ("Chatbot"). Para habilitar agentes autônomos baseados em LLM, precisamos diferenciar a estrutura de dados. O objetivo é permitir que o usuário escolha entre criar um fluxo "arrastar-e-soltar" ou um "Agente de IA" (configuração baseada em texto/prompt), sem misturar as interfaces.

**Valor para o usuário:** Permite criar assistentes inteligentes rapidamente sem a complexidade de desenhar nós, usando apenas prompts e configurações de modelo.

---

## Onde começa
- `ChatFlow` é agnóstico (usa `definition` JSON para tudo).
- Frontend assume visual builder (React Flow) para qualquer fluxo.
- Não existe conceito de "tipo de fluxo" explícito no banco.

## Onde termina
- `ChatFlow` possui `kind` (`chatbot` | `ai_agent`) e `agent_config`.
- Frontend força a escolha do tipo na criação.
- Editor adapta a interface: Canvas para Chatbot, Formulário para AI Agent.

---

## O que precisa ser feito

### No Backend (Rails 8 API)

1.  **Migration `AddKindToChatFlows`**:
    -   `kind`: integer, default: 0 (`chatbot`), not null.
    -   `agent_config`: jsonb, default: `{}`, not null.
    -   Index em `kind` para performance futura de filtros.

2.  **Model `ChatFlow`**:
    -   `enum kind: { chatbot: 0, ai_agent: 1 }`.
    -   Validação: `agent_config` deve ter schema válido se `kind: ai_agent` (pode ser simples `presence` por enquanto, mas preparado para `json_schema`).

3.  **Controller `Api::V1::ChatFlowsController`**:
    -   Permitir `kind` e `agent_config` nos `strong parameters`.
    -   **Padrão API:** Manter response envelope padrão (`{ data: flow }`).

### No Frontend (React + TS)

1.  **Types (`types/flow.ts`)**:
    -   Atualizar interfaces para refletir `kind` e `agent_config` (tipado, não `any`).

2.  **Componente `FlowTypeSelectionModal`**:
    -   **Design:** Modal limpo, duas cartas grandes (bento-style ou cards com ícones) explicando a diferença.
    -   "Chatbot": Ícone de fluxo, "Fluxo estruturado e regras fixas".
    -   "AI Agent": Ícone de robô/cérebro, "Inteligência autônoma baseada em prompt".

3.  **Componente `AIAgentConfigPanel`**:
    -   **Local:** Substitui o canvas do React Flow quando `kind === 'ai_agent'`.
    -   **Estilo:** Seguir padrão do **Painel Admin** (shadcn/ui cards, labels claros).
    -   **Campos:**
        -   Nome (Input).
        -   Modelo (Select: `gpt-4o`, `gpt-4-turbo`, `claude-3-5-sonnet`).
        -   Prompt do Sistema (Textarea com autosize, fonte mono para código).
    -   **Action:** Botão "Salvar" flutuante ou no header (consistente com builder atual).

4.  **Integração `ChatBuilderPage`**:
    -   Adicionar lógica de roteamento de view baseado em `flow.data.kind`.

---

## Observações importantes
-   **Retrocompatibilidade:** Todos os fluxos existentes SERÃO `chatbot` (0). A migration deve garantir isso via default.
-   **UX:** Não permitir alterar o `kind` após criação nesta versão (muito complexo migrar dados).
-   **Frontend Design:** Evite "neon/dark" genérico de IA. Use a paleta do Admin Panel (sóbrio, funcional, profissional).
-   **Testabilidade:** O backend deve garantir que `agent_config` não seja salvo com lixo.

---

## Critérios de aceite (Demonstráveis)

1.  **Backend:**
    -   [ ] `ChatFlow.create!(kind: :ai_agent)` funciona e persiste `1` no banco.
    -   [ ] `ChatFlow` criado sem `kind` assume `chatbot`.

2.  **Frontend:**
    -   [ ] Clicar em "Novo Fluxo" abre modal de seleção.
    -   [ ] Escolher "AI Agent" redireciona para a URL do builder.
    -   [ ] O Builder carrega o `AIAgentConfigPanel` (sem React Flow visível).
    -   [ ] É possível digitar um prompt, escolher modelo e salvar.
    -   [ ] Recarregar a página mantém os dados preenchidos.

---

## Dependências
-   Nenhuma.

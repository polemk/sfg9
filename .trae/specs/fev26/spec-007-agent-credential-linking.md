# Tarefa 007: Conectar Agente às Credenciais

**Sprint:** 3 - Integração e Configuração Avançada
**Estimativa:** 0.5 dia
**Tipo:** Frontend + Backend

---

## Contexto
Agora que temos agentes (Tarefa 004) e credenciais (Tarefa 005/006), precisamos ligar os dois. O usuário deve selecionar qual credencial o agente usará para se comunicar com o modelo escolhido.

**Valor para o usuário:** Capacidade operacional. O agente deixa de ser uma configuração inerte e passa a ter acesso aos meios de execução.

---

## Onde começa
- `AIAgentConfigPanel` existe mas seleciona apenas modelo e prompt.
- `ChatFlow` tem `agent_config`.
- `credentials` existem no banco.

## Onde termina
- `agent_config` passa a ter um campo `credential_id`.
- UI permite selecionar uma credencial compatível (ou qualquer uma, se simplificarmos).

---

## O que precisa ser feito

### No Frontend

1.  **Atualizar `AIAgentConfigPanel`**:
    -   Adicionar campo "Credencial" (Select).
    -   Carregar lista de credenciais disponíveis via API (`/api/v1/credentials`) no `mount`.
    -   **UX:** Se a lista estiver vazia, mostrar link "Cadastrar nova credencial" que abre o modal da Tarefa 006 (ou redireciona).

2.  **Filtragem Inteligente (Opcional/Nice to have)**:
    -   Se o usuário seleciona modelo `gpt-4`, idealmente filtrar apenas credenciais `openai`. (Pode ficar para depois se complicar, assumir lista completa por enquanto).

### No Backend

1.  **Validação (Execução - Futuro)**:
    -   Nesta tarefa, apenas garantir que o `credential_id` está sendo salvo no JSON `agent_config`.
    -   Não precisamos implementar a execução do agente aqui, apenas a configuração.

---

## Observações importantes
-   **Hick's Law:** Se o usuário tiver muitas credenciais, um Select simples pode ser ruim. Se for < 10, Select é ok. Se > 10, Combobox com busca.
-   **Dependência Cíclica de UX:** O usuário pode estar criando o agente e perceber que não tem a chave. Facilitar o cadastro sem perder o contexto do agente é crucial (Link para nova aba ou Modal sobreposto).

---

## Critérios de aceite

1.  **Frontend:**
    -   [ ] Dropdown de credenciais carrega dados do backend.
    -   [ ] Selecionar uma credencial atualiza o state.
    -   [ ] Salvar o agente persiste o `credential_id`.
    -   [ ] Ao recarregar o agente, a credencial correta vem pré-selecionada.

---

## Dependências
-   Tarefa 004 (Agente Base).
-   Tarefa 005 (Listagem de Credenciais).

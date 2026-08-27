# Tarefa 2.1 e 2.2: Visualizador de Execução de Fluxos (Execution Viewer)

**Sprint:** 2 - Analytics
**Estimativa:** 2-3 dias
**Tipo:** Backend + Frontend

---

## Contexto
Atualmente, não temos visibilidade detalhada do que acontece dentro de uma sessão de chat. Sabemos apenas o estado final. Para depurar fluxos complexos e analisar engajamento (onde os usuários desistem? qual caminho escolhem?), precisamos de um log de execução visual.
A ideia é ter um "Execution Control" ou "Viewer" que permita inspecionar sessões passadas, vendo passo-a-passo quais nós foram ativados, quais variáveis foram setadas e qual foi o input do usuário.

---

## Onde começa
- `ChatSession` armazena `context` (estado final) e `current_step_id`.
- `ExecutionLog` existe no hook `useChatFlow` (frontend, efêmero), mas não é persistido estruturadamente no banco para análise histórica.

## Onde termina
- Tabela `flow_executions` (ou similar) armazena histórico de passos.
- Interface no Admin Panel permite listar execuções e visualizar detalhes (timeline).

---

## O que precisa ser feito

### No Backend (Tarefa 2.1)

1. **Modelagem**:
    - Criar tabela `flow_executions` ou `session_steps`:
        - `chat_session_id` (FK)
        - `flow_id` (FK)
        - `node_id` (string)
        - `node_type` (string)
        - `input_data` (jsonb, input do usuário naquele passo)
        - `output_data` (jsonb, variáveis setadas/decisões)
        - `created_at` (timestamp)

2. **Flow Engine Hook**:
    - Instrumentar o `Ai::FlowEngine` para gravar um registro nessa tabela a cada passo processado (`process!`).

### No Frontend (Tarefa 2.2)

1. **Lista de Execuções**:
    - Criar página "Histórico de Execuções" dentro de "Chat Builder" ou "Analytics".
    - Listar sessões recentes (Lead, Fluxo, Data, Status).

2. **Detalhe da Execução (Viewer)**:
    - Ao clicar em uma execução, abrir gaveta/modal.
    - Exibir **Timeline Vertical**:
        - Passo 1: Start (Timestamp)
        - Passo 2: Pergunta "Qual seu nome?" -> Input Usuário: "Gui" (Variável `name` = "Gui")
        - Passo 3: Redirect -> `#pricing`
    - Visualizar variáveis que mudaram em cada passo.

---

## Observações importantes
- **Performance**: Logs de execução podem crescer rápido. Considerar limpar logs antigos após X dias ou usar banco separado/tabela particionada no futuro. Para MVP, tabela simples ok.
- **Privacidade**: Cuidado com dados sensíveis nos logs.

---

## Critérios de aceite
1. O dev deve realizar uma conversa com o bot.
2. No painel admin, deve aparecer essa nova execução.
3. Ao abrir o detalhe, deve mostrar a sequência exata de nós percorridos e os inputs fornecidos.
4. Deve mostrar o valor das variáveis capturadas em cada passo.

---

## Dependências
Tarefas da Sprint 1 (recomendado, mas não bloqueante).

## Próxima tarefa
Análise de funil (agregados).

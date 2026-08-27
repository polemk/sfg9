# Tarefa 1.1: End Node - Flow Handoff (Conexão entre Fluxos)

**Sprint:** 1 - Flow Connections & User Continuity
**Estimativa:** 1.5 dias(s)
**Tipo:** Backend + Frontend

---

## Contexto
Atualmente, os fluxos do Chat Builder são isolados. Para criar experiências complexas e modulares (como transferir o usuário de um "Bot de Vendas" para um "Bot de Suporte"), precisamos de um nó que conecte um fluxo ao outro. O "Handoff Node" atua como um "teletransporte". É imperativo que as variáveis coletadas até o momento não sejam perdidas e que a IA do novo fluxo inicie a conversa com uma saudação contextualizada (uma "mensagem inicial padrão"), em vez de responder à palavra-chave que acionou a transferência.

---

## Onde começa
- O `FlowEngine` e a IA processam nós sequencialmente atrelados a um único `flow_id`.
- O Builder tem blocos isolados e não possui o conceito de troca inter-fluxos.

## Onde termina
- O Builder passa a ter o nó "Jump to Flow / Handoff".
- Ao ser acionado, backend atualiza a `ChatSession`, mantém o `context` intacto.
- O Widget atualiza nome e avatar do bot para o novo fluxo.
- O novo fluxo envia automaticamente uma mensagem inicial amigável (sem reprocessar a última keyword do usuário).

---

## O que precisa ser feito

### No Backend
- **Novo Nó:** Criar `Ai::Nodes::Handoff`. Configuração deve armazenar `target_flow_id` e opcionalmente uma `custom_welcome_message`.
- **Engine Logic:** Modificar `Ai::FlowEngine` ou gerenciador da sessão. Quando encontrar o nó Handoff:
  1. Atualize a `ChatSession.chat_flow_id` para o novo fluxo.
  2. Resete o cursor/estado de nó (ex: `current_step_id`), exceto o `context` (variáveis).
- **Tratamento da Saudação:** Identificar que a sessão sofreu handoff e disparar a mensagem inicial padrão do novo fluxo/IA, enviando-a via Action Cable. Não passar a última mensagem do usuário como um "prompt solto" se ela foi apenas um comando de navegação.

### No Frontend
- **Builder UI:** Desenvolver o componente do nó "Handoff" permitindo selecionar `Flows` existentes via dropdown (buscar via API `/api/v1/admin/chat_flows`).
- **Widget UI:** Escutar eventos WebSocket de "flow_changed" para atualizar o header (Avatar/Nome) do chatbot ativo em tempo real, proporcionando uma transição elegante e sem reload usando Tailwind para a suavidade (ex: `transition-opacity`).

---

## Observações importantes
- **Prevenção de Loops:** Tome cuidado para evitar handoffs circulares (Fluxo A -> B -> A). Recomendado limitar a profundidade do stack ou apenas logar um warning.
- **TDD Workflow:** Utilize a metodologia RED-GREEN-REFACTOR. Escreva o teste testando se `session.chat_flow_id` muda quando o nó executa *antes* de implementar a lógica.

---

## Critérios de aceite
1. O desenvolvedor deve conseguir criar dois fluxos distintos (Fluxo A e Fluxo B) no Builder.
2. O desenvolvedor deve conseguir arrastar e linkar um nó Handoff no Fluxo A apontando para B.
3. No Widget, ao atingir o nó em A, a transição para B ocorre magicamente sem reload da página.
4. O Avatar e o Nome do topo do widget devem mudar para refletir as configs do Fluxo B.
5. O Fluxo B deve disparar a primeira mensagem sem responder com a keyword que acionou o handoff.
6. Uma variável "{{nome}}" fornecida no Fluxo A tem que estar presente no Fluxo B.

---

## Dependências
- Rota de listagem de fluxos ativos no backend para a ComboBox do construtor.

## Próxima tarefa
- Tarefa 1.2: End Node - Redirect & Account Creation

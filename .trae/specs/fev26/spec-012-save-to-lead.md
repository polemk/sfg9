# Tarefa 2.1: Save to Lead Node (Integração de Leads)

**Sprint:** 2 - Intelligence & Lead Generation
**Estimativa:** 2 dia(s)
**Tipo:** Backend

---

## Contexto
Durante o diálogo, o chat solicita ou descobre espontaneamente informações valiosas através das variáveis (`session.context`), como nome, e-mail da empresa ou cargo do usuário. Contudo, essa informação fica confinada no documento do chat. Para marketing, vendas e CRM, precisamos estruturá-la. O nó "Save to Lead" fará a ponte entre o contexto do chat em tempo-real e a tabela estruturada de `Leads`.

---

## Onde começa
- Variáveis são capturadas (`email`, `nome`, `idade`) mas só servem para re-renderização em templates (ex: "Olá {{nome}}").
- O fluxo de funil e pipeline de vendas (`CRM`) não recebe nada dessas conversas. Não há registro consolidado se o chat apenas finalizar.

## Onde termina
- O criador do fluxo arrasta um nó de "Salvar Lead" mapeando variáveis soltas do chat (`user_email`) para os campos reais do Model (ex: `Lead.email`).
- O backend automaticamente encontra ou cria (`find_or_create_by`) o Lead correspondente quando este nó é percorrido e atualiza com os dados mais frescos extraídos.

---

## O que precisa ser feito

### No Backend
- **Novo Nó (Action):** `Ai::Nodes::SaveToLead`. Ele deve aceitar um `field_mapping` (um Hash do tipo `{ "lead_name": "{{user_name}}", "lead_email": "{{user_email}}" }`).
- **Lógica de Salvamento:**
  - Extrair os valores do `session.context` substituindo (interpolando) os placeholders configurados na property do nó.
  - Usar o email inserido (ou o telefone/WA) como Primary Key lógica.
  - O Service invocado (`Leads::Creator` ou Similar) recebe os atributos mesclados. Ele deve executar um `UPSERT`.
- **Tratamento Híbrido AI Chatbot:** Se o bot for do tipo "AI Agent", devemos garantir que o agente não pule a execução dessa verificação. Idealmente, o webhook do AgentService também consiga invocar este serviço como uma "Tool", ou este nó continue válido no fluxo base estruturado. (O pedido do usuário fala em permitir criar leads "usando ai chats", então a arquitetura híbrida ou "Function Calling" da IA deve estar ciente disso).

### Tratamento de Formato RAG & Função (IA)
- O `Ai::AgentService` poderá interagir com a função `update_lead_info` via "Tool calling" (Anthropic/OpenAI) caso seja um chat puramente agente, ou o FlowBuilder estruturado executa o próprio `SaveToLead`.

---

## Observações importantes
- Mapeie campos como Name, Email, Phone de forma forte (fortemente tipada). Os campos excedentes que o usuário capturar e quiser salvar devem ir para um hash `custom_fields` da tabela de `Leads`.
- Caso haja um `user_id` no header real da aplicação, associe esse Lead criado à conta Master (Tenant) do criador do bot, para que as restrições de Role (`Admin`, `Super`) o vejam na dashboard correta.

---

## Critérios de aceite
1. Configurar um nó para salvar Lead, mapeando `{{user_name}}` -> `name` e `{{empresa}}` -> `company`.
2. Simular uma conversa e responder às informações.
3. Ao atingir o nó, o backend processa o `UPSERT`.
4. Ir no console / PostgreSQL Rails e verificar que foi inserida uma tupla na tabela de Leads com `name` e `company` corretos.
5. Em execuções consecutivas com a mesma primary key lógica (`email`), apenas dar `update` sem criar duplicatas agressivamente.
6. A execução do nó em falha (ex: constraint database error) deve gerar Warning Log, mas não parar a conversa visualmente para o lead final.

---

## Dependências
- Model de Leads já deve existir com sua capacidade de reter `custom_fields` (tipicamente jsonb postgres).

## Próxima tarefa
- Tarefa 2.2: Image Input & OCR com Claude

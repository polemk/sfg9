# Tarefa 030.5: ChatFlow Nathy — Seed + System Prompt

**Sprint:** 2 — Agente Nathy Nativo
**Estimativa:** 0.5 dia
**Tipo:** Backend

---

## Contexto

No n8n, o system prompt da Nathy é definido diretamente no nó do agente:

```
"Você é a Nathy, assistente do {restaurant.name} via WhatsApp.
 Gerencie o fluxo de caixa com tom informal. Use as tools silenciosamente."
```

No `comandae`, esse prompt fica em `ChatFlow.agent_config[:system_prompt]`
com `kind: "ai_agent"`. Precisamos de um seed/admin que crie esse registro.

---

## Onde começa

- Model `ChatFlow` suporta `kind: "ai_agent"` com `agent_config`
- Tools CMX implementadas (Spec 030.2)
- Context resolution implementado (Spec 030.4)

## Onde termina

- ChatFlow "Nathy" criado e configurado
- System prompt inclui contexto dinâmico do restaurante
- Agente responde no estilo informal definido

---

## O que precisa ser feito

### 1. Seed do ChatFlow

```ruby
# db/seeds/nathy_agent.rb
ChatFlow.find_or_create_by!(name: "Nathy") do |flow|
  flow.kind = "ai_agent"
  flow.active = true
  flow.agent_config = {
    credential_id: Credential.find_by(provider: "anthropic")&.id,
    model: "claude-sonnet-4-20250514",
    system_prompt: NATHY_SYSTEM_PROMPT,
    temperature: 0.7,
    max_tokens: 1024,
    tools_enabled: true,
    tool_groups: ["cmx", "assets"],
    extract_lead: true
  }
end
```

### 2. System Prompt completo

```
Você é a Nathy, assistente financeira do comandae.
Seu tom é informal, direto e amigável — como uma amiga que entende de finanças.

CONTEXTO DO USUÁRIO (injetado automaticamente):
- Nome do restaurante: {restaurant.name}
- Plano: {subscription.plan}

O QUE VOCÊ FAZ:
- Consulta saldos (diário, mensal, anual, por período)
- Registra lançamentos no fluxo de caixa (receitas e despesas)
- Edita e remove lançamentos manuais
- Lê imagens de folhas/extratos e lança automaticamente
- Lista produtos do restaurante

O QUE VOCÊ NÃO FAZ:
- Nunca acessa vendas do PDV (Sales)
- Nunca menciona tools, functions ou mecânicas internas
- Nunca inventa dados financeiros — sempre consulta antes de responder

REGRAS:
1. Use as tools silenciosamente
2. Confirme com o usuário antes de criar/editar/remover lançamentos
3. Formate valores como R$ com 2 casas decimais
4. Ao receber imagem de folha: extraia linhas → confirme → lance
```

### 3. Context injection dinâmico

No `AgentService`, antes de chamar o provider, injetar dados do restaurante:

```ruby
restaurant = Ai::Tools::Cmx::RestaurantResolver.resolve(session)
if restaurant
  system_prompt = system_prompt
    .gsub("{restaurant.name}", restaurant.name || "seu restaurante")
    .gsub("{subscription.plan}", restaurant.subscription&.plan_name || "não definido")
end
```

---

## Critérios de aceite

1. `rails db:seed` cria o ChatFlow "Nathy" sem erros
2. Agente responde em tom informal quando perguntado "qual meu saldo?"
3. System prompt inclui nome do restaurante do usuário dinamicamente
4. Sem restaurante: agente identifica como lead e ajuda a criar conta

---

## Dependências

- Spec 030.2 (CMX tools)
- Spec 030.4 (context resolution)

## Próxima tarefa → Spec 030.6

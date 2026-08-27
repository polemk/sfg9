# Tarefa 030.4: Resolução de Contexto — Telefone → Usuário ou Lead

**Sprint:** 2 — Agente Nathy Nativo
**Estimativa:** 0.5 dia
**Tipo:** Backend

---

## Contexto

O agente não usa operação como contexto obrigatório. A resolução é automática:

- Se o telefone que mandou mensagem pertence a um `User` cadastrado →
  o agente acessa dados do restaurante daquele usuário
- Se não pertence → trata como `Lead` e segue fluxo de conversão

Isso permite que o mesmo agente funcione tanto como
assistente financeiro (para clientes) quanto como vendedor (para leads).

---

## Onde começa

- `Lead` já é criado/associado nos webhooks
- `User` tem campo `phone`
- `AgentService` recebe `session` (que tem `lead`)

## Onde termina

- Todas as CMX tools recebem `restaurant` resolvido a partir do lead/user
- Se não há restaurante, tools financeiras retornam mensagem amigável

---

## O que precisa ser feito

### 1. Método `resolve_restaurant` no contexto de tools

```ruby
# Em Ai::Tools::Cmx (concern ou módulo compartilhado)
module Ai::Tools::Cmx::RestaurantResolver
  def self.resolve(session)
    lead = session.lead
    return nil unless lead

    # 1. Buscar usuário pelo telefone do lead
    user = User.find_by(phone: lead.phone) if lead.phone.present?

    # 2. Retornar restaurante do usuário
    user&.restaurant
  end
end
```

### 2. Todas as CMX tools usam esse resolver

```ruby
restaurant = Ai::Tools::Cmx::RestaurantResolver.resolve(session)
if restaurant.nil?
  return { success: false, message: "Você ainda não tem um restaurante cadastrado. Deseja criar uma conta?" }
end
```

### 3. Comportamento para leads sem conta

Quando `restaurant` é nil, o agente deve:
- Não expor tools financeiras (ou retornar mensagem amigável)
- Focar em FAQ, ajuda sobre o app e conversão para criação de conta

---

## Critérios de aceite

1. Usuário com telefone cadastrado → tools retornam dados do restaurante dele
2. Lead sem conta → tools retornam "Você ainda não tem um restaurante"
3. Dois usuários com restaurantes diferentes → dados isolados
4. Teste: `RestaurantResolver.resolve(session)` com user existente e sem user

---

## Dependências

- Models `User`, `Restaurant`, `Lead` existem
- Lead tem campo `phone`

## Próxima tarefa → Spec 030.5

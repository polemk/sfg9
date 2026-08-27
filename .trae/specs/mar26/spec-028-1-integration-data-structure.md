# Tarefa 028.1: Estrutura de Dados de Integração (Integration Model)

**Sprint:** 1 - Fundações Omnichannel (Hub Meta)
**Estimativa:** 1 dia(s)
**Tipo:** Backend

---

## Contexto
Atualmente, o sistema suporta comunicação via WhatsApp de modo não-oficial utilizando a Evolution API. Essa conexão possui forte acoplamento com o modelo `PolemkInstance`. 
Para avançarmos no mercado e atendermos de forma resiliente, precisamos integrar canais nativos da Meta (WhatsApp Business API WABA, Instagram Direct, Facebook Messenger) e converter a arquitetura num verdadeiro gateway Omnichannel. 

O primeiro passo é criar uma estrutura de dados flexível que possa armazenar credenciais e tokens para qualquer provedor (Meta, Evolution, etc), permitindo que os bots e usuários respondam por diversas plataformas simultaneamente.

---

## Onde começa
- O banco atual depende das tabelas ligadas ao `EvolutionConnection` e `PolemkInstance`.
- Não existe uma tabela genérica para guardar as _chaves_ das APIs oficiais.

## Onde termina
- Uma nova tabela `integrations` criada via Migration.
- O Model ActiveRecord `Integration` devidamente configurado e associado aos outros modelos globais (ex: Bot/Account).

---

## O que precisa ser feito

### No Backend

1. **Migration `CreateIntegrations`:**
   Gerar e executar migration com os seguintes campos:
   - `id`: uuid (PK padrão do projeto)
   - `provider`: string (Ex: 'meta', 'evolution')
   - `platform`: string (Ex: 'whatsapp', 'instagram', 'messenger', 'evolution_wa')
   - `access_token`: text (Para guardar o System User Token da Meta ou a API Key da Evolution)
   - `external_id`: string (Identificador externo, ex: `Page ID` do Instagram ou `Phone Number ID` do WABA)
   - `status`: string (Ex: 'active', 'inactive', 'error')
   - `bot_id`: references (uuid) - Chave estrangeira ligando qual Bot é dono dessa integração.
   - `timestamps` padrão do Rails.
   
2. **Setup do Model `Integration`:**
   - Criar `app/models/integration.rb`.
   - Incluir as associações (`belongs_to :bot`).
   - Adicionar validações de presença para `provider`, `platform` e `access_token`.

3. **Injetar Constantes e Enums:**
   - Para facilitar buscas, definir Enums ou constantes para `provider` e `platform`.
   - Exemplo: `enum platform: { whatsapp: 'whatsapp', instagram: 'instagram', messenger: 'messenger', evolution_wa: 'evolution_wa' }`

---

## Observações importantes
- Essa modelagem é projetada para o futuro. Mesmo que nesta Sprint não migremos o 100% dos fluxos antigos do Evolution, a tabela já precisa prever o campo para tal.
- No caso do Instagram, o `external_id` será a **IG Page ID**. No WhatsApp Oficial, será o **Phone Number ID**. Isso será a chave de mapeamento na hora de responder os leads.

---

## Critérios de aceite
O dev deve demonstrar que:
1. Ao rodar `rails db:migrate`, a tabela `integrations` é criada com sucesso, com PK = UUID.
2. É possível instanciar um `Integration.create!` via console com os dados preenchidos associados a um bot.
3. Se falhar no preenchimento de `provider` ou `access_token`, o Rails recusa a operação com o erro correto de validação de model.

---

## Dependências
- Nenhuma. É a tarefa base.

## Próxima tarefa
- **Tarefa 028.2:** Criar os controllers e rotas no Grape para receber e validar os Webhooks oficiais que farão uso dos tokens que serão guardados nesta nova tabela.

# Tarefa 024: Integrações Omnichannel (Meta e Evolution API)

**Sprint:** Sprint 4 - Integrações e Escalonamento
**Estimativa:** 3 dia(s)
**Tipo:** Backend + Frontend

---

## Contexto
Atualmente, o sistema suporta o WhatsApp de modo não-oficial via Evolution API com forte acoplamento no modelo `PolemkInstance`. 
Para avançarmos no mercado e atendermos de forma resiliente, precisamos integrar canais nativos da Meta (WhatsApp Business API WABA, Instagram Direct, Facebook Messenger), convertendo a arquitetura num verdadeiro gateway Omnichannel (similar ao ManyChat). O usuário (admin) informará as chaves e tokens na plataforma, as mensagens chegarão através de webhooks unificados e as respostas serão despachadas pela API adequada dependendo da origem.

---

## Onde começa
- `EvolutionConnection` atualmente gerencia toda a ponte de mensagens.
- `LeadCrossChannelService` já está perfeitamente preparado para matching inteligente no salvamento unificando conversas multiplataforma.
- Entendemos as regras via payload do webhook do n8n que já lida com os webhooks do Meta.

## Onde termina
- Sistema possuirá uma tabela de Integrações (`Integration` ou `Channel`) para guardar as chaves do Meta System User (Token perpétuo) e Evolution API.
- Sistema escutará os webhooks oficiais da Meta e despachará mensagens nativamente através de um Client/Adapter (`Omnichannel::DispatchService`).
- Frontend React possuirá uma página administrativa de "Gerenciador de Integrações" para os canais.

---

## O que precisa ser feito

### No Backend

1. **Camada de Dados (Integration):**
   - Criar model/migration `Integration` (`provider:string`, `platform:string`, `access_token:text`, `external_id:string`, `status:string`, `operation_id:uuid` opcional).
   - `provider` = 'meta' ou 'evolution'.
   - `platform` = 'whatsapp', 'instagram', 'messenger', 'evolution_wa'.

2. **Webhooks da Meta:**
   - Criar `app/controllers/api/v1/webhooks/meta.rb` (Grape API).
   - Rota `GET /api/v1/webhooks/meta` para responder o desafio `hub.challenge` com o valor original.
   - Rota `POST /api/v1/webhooks/meta` para lidar com mensagens de entrada (inbound), extrair conteúdo padrão e jogar pro motor do Agente IA.

3. **Despacho Omnichannel (Adapter):**
   - Criar `app/services/omnichannel/dispatch_service.rb`.
   - Abstrair envio (`send_text`, `send_media`). Verifica qual o Canal correspondente do Lead baseado no `target_id` gravado e `source_type`. Redireciona via chamada HTTP para a Graph API da Meta ou Evolution.

### No Frontend

1. **Tela de Integrações (/admin/integrations):**
   - Implementar `IntegrationsPage` com cards interativos.
   - Card para: WhatsApp Oficial (WABA), Instagram, Evolution API.
   - Drawer ou Modal para input manual de Tokens (`Access Token`, `Phone Number ID`, ou `Page ID`). Sem fluxo de leitura de QR Code.
   - Chamadas HTTP para a API Gravar/Listar a tabela Integration.

---

## Observações importantes
- **Regra de Janela de 24h da Meta:** Bloquear disparos nativos à API WABA quando o cliente exceder a janela de tempo de 24hs para um Agent Responder sem um pre-approved HSM template.
- O campo `target_id` do Lead é chave para encontrar qual `Integration` responde de volta. No caso de uma DM do IG, o `target_id` pode ser a IG page ID que cruzará com o `Integration.external_id`.

---

## Critérios de aceite
1. Admin cadastra um Access Token do Instagram via sistema (Frontend -> DB).
2. GET `/api/v1/webhooks/meta?hub.mode=subscribe&hub.challenge=123...` retorna 200 com content 123... (validação Meta de segurança de Webhooks).
3. O DispatchService envia mensagem via Graph API com sucesso usando tokens da base, após mensagem bater no Router Inbound de teste.
4. LeadCrossChannelService mantém o cruzamento de Leads normalmente para as mensagens que passam pelo Hub.

---

## Dependências
- Nenhuma dependência estrutural. Framework Grape de Webhooks e estrutura de Leads já são suficientes.

## Próxima tarefa
- Finalizar UI da Omnichannel Inbox (Agile CRM Style) ou refatoração do Flow Engine para suportar o novo hub.

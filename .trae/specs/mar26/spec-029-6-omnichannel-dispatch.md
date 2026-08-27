# Tarefa 030.1: Adapter de Envio Omnichannel (DispatchService)

**Sprint:** 3 - O Despachante Omnichannel
**Estimativa:** 2 dias
**Tipo:** Backend

---

## Contexto
Até a Sprint 2, nós construímos o "Inbound" (Capacidade de ouvir, ler e reagir instantaneamente) aos Webhooks da Meta e comentários.
No entanto, quando o Agente de IA decide responder a uma conversa (ou quando um Atendente Humano envia uma mensagem no Chat Inbox do Ai9), o sistema atual envia cegamente a mensagem usando a Evolution API. 
Para que o Ai9 seja verdadeiramente Omnichannel, o momento de *Saída* (Outbound) precisa de um roteador inteligente. Uma classe que puxe o Lead, analise "*Por onde esse lead fala com a gente?*" e utilize a API correta (Meta Graph API para Instagram/WABA, ou Evolution para WA não-oficial).

---

## Onde começa
- Todas as mensagens do Bot e de Atendentes chamam um `SendXMessageService` ou similar, que por baixo dos panos usa `EvolutionConnection`.
- O Lead possui o atributo ou metadado indicando por qual `source_type` ele chegou (ex: 'instagram', 'whatsapp').

## Onde termina
- O novo serviço `Omnichannel::DispatchService`.
- Nenhuma mensagem sai do Ai9 sem passar por esse Service. Ele atua como um Design Pattern *Adapter/Strategy*.
- Envia a mensagem pela tecnologia certa e retorna logs padronizados.

---

## O que precisa ser feito

### No Backend

1. **Criar a Interface de Roteamento:**
   - Criar `app/services/omnichannel/dispatch_service.rb`.
   - Método base: `call(lead:, message_body:, message_type: 'text', media_url: nil)`.

2. **Decisão de Rota (The Switch):**
   - Ler `lead.source_type` e/ou `lead.source_id`.
   - Localizar a `Integration` ativa daquele Bot compatível com o canal do Lead. (Ex: se o Lead veio do Instagram, buscar `Integration.find_by(bot_id: lead.bot_id, platform: 'instagram')`).
   - Se `platform == 'instagram' || 'messenger' || 'waba'`:
     - Acionar a respectiva Service de envio via Graph API (ex: `Meta::SendMessageService`), enviando usando o `access_token` da Integration.
   - Se `platform == 'evolution_wa'`:
     - Acionar o legado `Evolution::SendMessageService`.

3. **Padronização de Retorno e Gravação:**
   - O DispatchService deve ser agnóstico. Não importa por onde enviou, ele deve retornar `Hash` de sucesso/erro padronizado: `{ success: true, message_id: '123', delivered_at: Time.current }`.
   - Substituir as velhas chamadas diretas ao Evolution dentro dos Agents Workers pelo novo Roteador.
   
---

## Observações importantes
- A complexidade desta tarefa é média-alta porque exigirá um *Find & Replace* ou Refactoring em múltiplos pontos do código onde hoje o Ai9 assume que "Tudo é Evolution".
- Cuidado para preservar as regras de template. Se a Meta exigir HSM (Template) fora da Janela de 24 horas no WhatsApp Oficial, a API retornará falha se mandarmos um texto livre. Por ora, propague o Erro 400 normal da Meta no log. Lidar com Templates é escopo de uma Sprint Futura.

---

## Critérios de aceite
O dev deve demonstrar que:
1. Uma conversa inteira no Evolution WA funciona normalmente (Compatibilidade Legada não quebrada).
2. Uma conversa iniciada via Direct do Instagram (Simulada ou Real) recebe as respostas do Agente Inteligente diretamente no Inbox do App do Instagram sem falhas. O log deve registrar "Dispatched via Meta Graph API".
3. Lançar o RSpec para o `DispatchService` provando que ele roteia pro mock do Evolution se o Lead for de lá, ou pro Mock da Meta se o Lead for do Instagram.

---

## Dependências
- Todo o ciclo de Inbound (Sprints 1 e 2).

## Próxima tarefa
- **Fim da Sprint 3.** A plataforma Ai9 agora opera de forma 100% nativa com as APIs oficiais da Meta e gerencia Comentários como um motor de Aquisição!

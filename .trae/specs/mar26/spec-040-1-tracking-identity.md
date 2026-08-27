# Tarefa 040.1: Vínculo de Identidade do TrackedEvent (Backend & Frontend)

**Sprint:** 3 — Telemetria Comportamental & Mapa de Calor  
**Estimativa:** 1 dia  
**Tipo:** Backend + Frontend  

---

## Contexto

Atualmente o aplicativo possui a funcionalidade de auditoria baseada na emissão e salvamento de `tracked_events`. No entanto, eles gravam unicamente o `payload` bruto e um `session_uuid`. 
Se um visitante chega de uma campanha, navega por cinco minutos, lê a página de Vendas inteira e só então realiza o cadastro e se torna um `Lead`, todos os eventos rastreados nesse prelúdio estão sem pai; ou seja, isolados na tabela como tráfego "fantasma". O objetivo desta tarefa é amarrar os eventos estruturalmente com os respectivos Leads no banco de dados e garantir a retroatividade da jornada.

---

## Onde começa

1. O Model `TrackedEvent` já está criado e persistindo com um controlador primitivo na API.
2. Visitantes navegam deixando eventos com o `session_uuid` nativamente no frontend.
3. Fluxo de captura de Leads funcional gerando o próprio `Lead`.

## Onde termina

1. A tabela `tracked_events` tem uma Foreign Key opcional (`lead_id`).
2. O Endpoint `POST /api/v1/tracked_events` aceita inteligentemente o preenchimento do ID caso a origem contenha autenticação/cookie atrelado a um ID de sessão final.
3. Quando a rota de CRIAÇÃO do lead processa um sucesso, uma amarração automática converte as gravações anônimas passadas do `session_uuid` em histórico legítimo para o novo lead convertido.

---

## Fluxo

```
FRONTEND
└─> Usuário interage pela primeira vez → É gerado session_uuid local
    └─> Dispara TrackedEvents para o backend (Tabela de Eventos = [session_x, null_lead])

BACKEND
└─> Endpoint /api/v1/leads processa captura → Cria ID de Lead e finaliza a sessão de conversão
    └─> Dispara Job Sidekiq Pós-Conversão: `IdentityMatcherJob.perform_async(lead_id, session_identifier)`

JOB
└─> Atualiza em Background: `TrackedEvent.where(session_uuid: session_identifier).update_all(lead_id: lead_id)`
```

---

## O que precisa ser feito

### No Backend

1. **Migração do Banco de Dados**: Adicionar a referência opcional `reference :lead, foreign_key: true, null: true, type: :uuid` (ou index genérico) na tabela `tracked_events`.
2. **Atualização do Modelo**: Adicionar `belongs_to :lead, optional: true` em `TrackedEvent.rb`.
3. **Job de Conciliação de Identidade (`LinkEventsToLeadJob` ou equivalente)**: 
   - Criar um ActiveJob rápido que rode em fila de baixa prioridade.
   - Sua única finalidade é extrair todos os eventos que contenham o dado `session_uuid` (do header ou do payload armazenado antes) e preencher em massa (`update_all`) com o respectivo `id` recém criado na tabela de Leads.
4. **Acionamento Automático**: Pendurar o Job no fluxo final dentro do `LeadMessageService` (quando um Lead é gerado do Zero seja via chat, API direta, Meta webhooks com conversão de cookie etc).

### No Frontend

1. **Assegurar Transmissão**: Garantir que as lógicas que emitem os pedidos (no serviço React que intercepta eventos ou axios configs) não descartem o Local Storage ou Cache onde o `uuid` anônimo mora. Essa chave deve sobreviver à recarga ou redirecionamento inicial que acontece durante a transformação "Anônimo → Visão Painel".
2. **Adoção imediata (Hot-Bind)**: Se o JWT for adquirido de imediato por Login, passar a emitir o evento com as informações já portadas na instância de usuário, permitindo o armazenamento direto (ignorando a rota retroativa se o usuário já estiver ativo).

---

## Observações Importantes

Para lidar suavemente com integrações e webhooks onde o Meta não possui `session_uuid` para envio de lead, o Backend deve executar a tarefa graciosamente em *Fail-Safe*. O retrocesso baseia-se num "Session Identity" apenas para interações Web (Frontend em React).

---

## Critérios de aceite

1. Rodar `TrackedEvent.where.not(lead_id: nil).exists?` via consola do Rails deve trazer respostas lógicas de leads associados no passado ou presente.
2. Nenhuma interação isolada de um cadastro fresco com origens web seja deixada como orfã no sistema, o banco deve espelhar que todas as lógicas vindas perante aquele `uuid` formaram a identidade inicial do usuário.  
3. Injeção direta sem passar pelo Job quando o frontend autenticado emitir "Scrollou" pela Dashboard privada, acoplando instantaneamente ao `lead_id`.

---

## Dependências

Nenhuma dependência externa. Essa é a Tarefa Primária do Novo motor de Analytics estabelecendo a base para o Heatmap e o High Watermark.

## Próxima tarefa → Tarefa 040.2
- Adoção de Filtro (High Watermark/Debounce) para o Event Tracking Atual de Rota e Scroll no React.

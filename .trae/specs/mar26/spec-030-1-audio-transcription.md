# Tarefa 030.1: Suporte a Áudio em Todos os Canais

**Sprint:** 1 — Base Multicanal
**Estimativa:** 1 dia
**Tipo:** Backend + Frontend (endpoint)

---

## Contexto

No n8n (`dsl-router-v1`), o bloco de áudio baixava a mídia da Evolution,
convertia para buffer e chamava OpenAI Whisper STT. No `comandae`, esse
comportamento precisa funcionar em **todos os canais**:

- **WABA / Evolution API**: mensagem com `mediaType: "audio"` + `mediaUrl`
- **Instagram DM**: campo `attachments[0].type == "audio"`
- **Messenger**: `messaging[0].message.attachments[0].type == "audio"`
- **AI Chat Widget**: upload binário de arquivo pelo browser

Sem transcrição, o agente não consegue entender mensagens de voz.

---

## Onde começa

- Webhook `messages-upsert` (Evolution) existe mas está vazio (sem processamento).
- Webhook Meta (IG/Messenger) não tem tratamento de áudio.
- Widget `POST /api/v1/public/chat` existe para texto.
- Credencial `openai` já cadastrada via `Credential`.

## Onde termina

- Em qualquer canal, áudio enviado é transcrito e processado como texto.
- `LeadMessage` salva com `content_type: "audio"` e transcrição em `content`.
- Widget tem endpoint funcional para upload de áudio.

---

## O que precisa ser feito

### 1. Criar `Ai::AudioTranscriptionService`

```
backend/app/services/ai/audio_transcription_service.rb
```

Interface:
```ruby
Ai::AudioTranscriptionService.transcribe(
  media_url: "https://...",   # para webhooks (WABA/IG/Messenger)
  audio_data: <StringIO>,     # para widget (upload binário)
  language: "pt",
  api_key: "sk-..."           # da Credential openai
)
# => { success: true, text: "transcrição aqui" }
# => { success: false, error: "motivo" }
```

- Download via Faraday (Evolution: header `apikey`; Meta: header `Bearer`)
- Formato: `.ogg` (Evolution), `.mp4` (Meta) — Whisper aceita ambos
- Em memória: `StringIO`, não salvar em disco
- Fallback: se falhar, retornar `nil` e logar, sem quebrar o fluxo

### 2. Ativar `messages-upsert` no webhook Evolution

O endpoint existe mas está comentado. Ativar para:
1. Detectar `mediaType == "audio"` no payload
2. Chamar `AudioTranscriptionService.transcribe`
3. Criar `LeadMessage` com texto transcrito e `content_type: "audio"`
4. Encaminhar para o ChatFlow/AgentService normalmente

### 3. Tratar áudio nos webhooks Meta (IG DM + Messenger)

Detectar `attachments[0].type == "audio"` e seguir mesmo padrão,
usando token Meta para download.

### 4. Novo endpoint no Widget

```
POST /api/v1/public/chat/audio
```

Params: `file` (multipart), `session_token`, `flow_id`

Recebe o `file`, passa para `AudioTranscriptionService.transcribe(audio_data: ...)`,
depois entra no fluxo normal do chat público com o texto transcrito.

---

## Observações

- Prefixar `[🎤 Áudio]: ` na `LeadMessage` para diferenciação visual
- Downloads Evolution: header `apikey: ENV['EVOLUTION_API_KEY']`
- Downloads Meta: header `Authorization: Bearer {page_access_token}`

---

## Critérios de aceite

1. Áudio pelo WhatsApp → agente responde ao conteúdo da fala
2. `LeadMessage` criada com `content_type: "audio"` e transcrição em `content`
3. Widget: `POST /chat/audio` aceita upload e retorna resposta do agente
4. Falha de transcrição loga e não gera 500
5. Testes:
   - `spec/services/ai/audio_transcription_service_spec.rb`
   - Sucesso com `media_url` (WebMock)
   - Sucesso com `audio_data` (StringIO)
   - Falha de download
   - Falha de Whisper (chave inválida)

---

## Dependências

- Credential `openai` no banco
- Evolution API configurado com webhookBase64 ou mediaUrl

## Próxima tarefa → Spec 030.2

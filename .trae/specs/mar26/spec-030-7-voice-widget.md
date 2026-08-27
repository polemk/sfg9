# Tarefa 030.7: Widget de Voz — Endpoint + MediaRecorder

**Sprint:** 3 — Agentic Mode + Widget
**Estimativa:** 1 dia
**Tipo:** Backend + Frontend

---

## Contexto

Todos os canais devem suportar áudio, inclusive o chat widget no browser.
Isso requer gravação de áudio no frontend e envio para transcrição no backend.

---

## Onde começa

- `Ai::AudioTranscriptionService` (Spec 030.1) transcrevendo áudio
- Endpoint `POST /api/v1/public/chat` processando texto
- Agent Sidebar (Spec 030.6) renderizando o chat

## Onde termina

- Botão de microfone no chat (widget e sidebar)
- Áudio gravado → transcrito → processado como texto pelo agente

---

## O que precisa ser feito

### Backend

#### Endpoint de upload de áudio

```
POST /api/v1/chat/audio  (autenticado, para sidebar)
POST /api/v1/public/chat/audio  (público, para widget)
```

Params: `file` (multipart audio/webm ou audio/ogg), `session_token` ou JWT, `flow_id`

Fluxo:
1. Receber arquivo
2. `AudioTranscriptionService.transcribe(audio_data: file)`
3. Se sucesso: entrar no fluxo normal do chat com texto transcrito
4. Retornar resposta do agente

### Frontend

#### Componente `VoiceRecordButton`

```tsx
// Hook: useVoiceRecorder
const { isRecording, startRecording, stopRecording, audioBlob } = useVoiceRecorder()
```

- `MediaRecorder API` com `audio/webm;codecs=opus`
- Botão: press-and-hold ou toggle
- Visual: animação de ondas/pulsação durante gravação
- Ao parar: envia via `FormData` para endpoint de áudio
- Feedback: loading spinner durante transcrição

#### Integração

- Adicionar `VoiceRecordButton` ao lado do botão de enviar no chat
- Funciona tanto no widget público quanto no Agent Sidebar
- Após transcreve, exibe o texto na mensagem do usuário com ícone 🎤

---

## Critérios de aceite

1. Pressionar microfone → iniciar gravação com feedback visual
2. Soltar/clicar → para gravação e envia áudio
3. Backend recebe, transcreve e responde como texto normal
4. `LeadMessage` salva com `content_type: "audio"`
5. Funciona no Chrome e Firefox (Safari: verificar suporte MediaRecorder)
6. Testes: endpoint aceita multipart, retorna resposta do agente

---

## Dependências

- Spec 030.1 (AudioTranscriptionService)
- Spec 030.6 (Agent Sidebar) para ponto de integração

## Conclusão do Roadmap

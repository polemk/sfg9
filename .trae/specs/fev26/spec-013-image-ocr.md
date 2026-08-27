# Tarefa 2.2: Image Input & OCR (AI Vision Integration)

**Sprint:** 2 - Intelligence & Lead Generation
**Estimativa:** 2.5 dias
**Tipo:** Backend + AI Integration + Frontend

---

## Contexto
O atual AI Builder e chatbots clássicos lidam somente com texto bruto. Para indústrias financeiras, clínicas ou B2B pesadas, permitir o upload de um comprovante, rascunho ou foto e ter a inteligência artificial (Claude Sonnet 3.5+ Vision) "lendo e extraindo" informações com perfeição pode alavancar radicalmente a conversão de tempo real. Não é apenas tesseract puro (OCR burro), mas uma instrução inteligente aplicada sobre a foto enviada ("leia este cardápio e refine seus itens").

---

## Onde começa
- O Widget recusa ou não tem opção de upload de ficheiros de imagem (jpg, png).
- O motor `AgentService` ou `FlowEngine` lida unicamente com o tipo "texto" das `lead_messages`.

## Onde termina
- O usuário encontra um ícone de anexo no input de texto do Chat Widget.
- O Frontend faz upload binário (`ActiveStorage` ou direto Base64 pra um endpoint `/api/v1/chat/upload`).
- O Backend despacha a mensagem com um objeto `image_url` ou `base64` acoplado ao provider `anthropic_provider.rb`.
- O Claude processa a imagem como parte dos "Role: User", "Content: Text + Image block".

---

## O que precisa ser feito

### No Backend
- **Endpoint Upload:** Adicionar capacidade de receber form-data com um file upload. Persistir a mídia (via ActiveStorage no Model `LeadMessage`).
- **Provider Adequação:** 
  - Atualizar o `anthropic_provider.rb` (e subsequentemente OpenAI se desejar usar gp-4o) para mapear quando houver anexo.
  - Para o Claude: Ele exige mensagens num formato `Array` de blocos de `type: "image"` + `source: { type: "base64", media_type: ..., data: ... }`.
- **System Prompt Extra:** Permitir que o nó ou a IA entenda instruções específicas sobre como lidar caso o usuário apenas atire fotos sem descrição textual.

### No Frontend
- **Widget Interface:** 
  - Adicionar o botão de (📎) Clip ao lado do Input (ou Drag & Drop no painel do chat).
  - Estado de `Uploading...` (Skeleton loader na bolha lateral direita - User).
  - Preview nativo: Renderizar a foto na bolha de mensagem enviada no histórico usando `<img />` com Tailwind.
- **Requisição:** Adaptar a request para utilizar a classe `FormData` se contiver anexos.

---

## Observações importantes
- **Performance de Payload:** Ao invés de mandar Base64 gigante na rede do frontend para o Ruby, considere mandar binary multipart/form-data. Já do Ruby pro Claude pode ser `base64`.
- **Limites:** Limitar em 5MB pra não estourar timeout / body payload excessivo no provider do Ruby.
- **Tipos Suportados:** Strict enforcement de MIME. Apenas `image/jpeg`, `image/png`, `image/webp`. Retornar erro legível se for `.pdf` (ou implementar parsing de PDF separadamente, mas foge ao MVP).

---

## Critérios de aceite
1. O desenvolvedor clica no clipe no componente AIChatWidget.
2. Seleciona uma JPG local e clica em ENVIAR. O chat mostra uma miniatura "Subindo".
3. A API do Rails processa o upload com ActiveStorage.
4. O Backend dispara o Payload formatado para a Anthropic (`type: image`).
5. A IA no backend responde sobre o conteúdo da imagem (Ex: "Parece um relógio analógico").
6. A resposta flui normalmente para o chat via interface de conversação regular.
7. Em nenhuma etapa deve ocorrer falhas de formatação ("Content not provided") via SDK.

---

## Dependências
- `AgentService` e provedor de Anthropic já parametrizado (feito na Sprint de Fundações).

## Próxima tarefa
- Tarefa 2.3: AI Chat Lead Generator

# Tarefa 2.3: Frontend Asset Shortcode Parser

**Sprint:** 2 - Agent Integration & Internal Tools
**Estimativa:** 1 dia
**Tipo:** Frontend

---

## Contexto
O modelo de linguagem devolverá algo na conversa final neste formato: `"Claro! Veja as imagens da portaria: [asset:PORT32] e [asset:PQ01]."`.
Contudo, exibir este texto curto para o Lead na UI é uma falha gráfica grave. O Chat Widget (e a página de histórico administrativo) de fato precisam ler este texto bruto, detectar a assinatura de "shortcode", bater em algum endpoint do backend e transformar `[asset:PORT32]` em uma imagem linda renderizada dentro da bolha da conversa do chat.

---

## Onde começa
O Backend possui tabelas e URLs públicas para exibição dos arquivos enviados pelas operações. O chat web intercepta o Stream de string de Markdown ou respostas finais diretas.

## Onde termina
A UI do Chat React deve extrair os shortcodes do bloco de texto e montar uma visualização "Card" do Asset na conversa, logo abaixo do parágrafo, mantendo o aspecto limpo e "WhatsApp-like" do atendimento.

---

## O que precisa ser feito

### No Frontend

1. **Expansão de Markdown Componente**:
   Na bolha do Chat de mensagens de IA (ex: `AIChatWidget` -> `ChatMessageBubble` ou o renderizador de Markdown customizado, como `react-markdown`), adicionar um `Plugin/Parser` customizado ou uma camada de substituição Regex simples.

2. **Regex Extractor**:
   Uma RegExp simples como `/\[asset:([A-Za-z0-9_]+)\]/g` para encontrar strings e seus shortcodes dentro do conteúdo original. Quando ele encontrar:
   - Apagar essa sub-string ou substituí-la por uma _preview skeleton_. 
   - Armazenar em um Array os IDs rastreados naquela mensagem (ex: `['PORT32', 'PQ01']`).

3. **Fetch dos Assets**:
   Os componentes React (que exibem as Mensagens) invocarão um utilitário (ex: Axios / SWR / React Query hook `useAssetsResolver(shortcodes)`) que bate em um endpoint do tipo `GET /api/v1/operations/assets/resolve?shortcodes=PORT32,PQ01`. O backend retornará as mídias formatadas (`{ PORT32: { url: "..", type: "image", title: "Portaria" }}`).

4. **Componente de Exibição**:
   Montar o `MediaPreviewCard.tsx`. Ele tratará:
   - Caso `image`: tag `<img>`.
   - Caso `video`: tag `<video>` muda nativa com opções de tela inteira.
   - Caso `document/pdf`: Link com ícone para _Download_.

### No Backend

1. **Endpoint `Resolver`**:
   O `Routes.rb` deve suportar o caminho onde se fará a Query dos shortcodes `['PORT32', 'PQ01']` de maneira paginada/em batch, retornando no formato JSON adequado com a URL já tratada (S3/ActiveStorage URL ou estática).

---

## Observações importantes
- Para a experiência imediata do widget de Chat, busque otimizar as chamadas: quando uma mensagem contém múltiplos shortcodes, em vez de N chamadas web via Axios, junte em um Array único e mande a busca otimizada (`resolve?keys=...`).
- Esse `[asset:*]` não deve ser indexável para SEO, então ele flui internamente restrito aos WebWidgets de conversas do Lead.
- Proteja o Regex de "injeções cruas" (ex: Lead manda o shortcode tentando espiar) garantindo que este Replace de Midia reaja **EXCLUSIVAMENTE** a nós de mensagens oriundas do sistema de Agente/Assistente (`role == 'assistant'`). O usuário (`role == 'user'`) não renderizará mídias do cache se ele próprio digitar `[asset:XXX]`.

---

## Critérios de aceite
Para considerar esta tarefa concluída, o dev deve demonstrar:

1. A digitação simulada por um Developer via botão "Mock Agent Message" com o texto "Veja aqui [asset:FAKE123]" e mostrando que a requisição de API com `FAKE123` e a renderização do Skeleton e a Foto final aconteceu fluidamente.
2. Comprovar que blocos que apenas mimetizam aspas não quebram o parsing.
3. Demonstração de que a Message de um Client `role: user` contendo a mesma string sai inalterada no frontend, livre de expansão.

---

## Dependências
- Backend (Model OperationAsset preparado) – Tarefas em Sprint 1.

## Próxima tarefa
Tarefa 3.1: Operations Metrics Backend API (`spec-023-operations-metrics-api.md`)

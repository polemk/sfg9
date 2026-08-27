# Tarefa 040.3: O Motor de Coleta do Mapa de Calor (Frontend Dashboard)

**Sprint:** 3 — Telemetria Comportamental & Mapa de Calor  
**Estimativa:** 1 a 2 dias  
**Tipo:** Frontend (React)

---

## Contexto

Um rastreador (tracker) isolado e tático. É assim que precisaremos capturar os comportamentos analíticos dos leads de forma que possamos traduzir o invisível: os toques reais ocorridos e sua distribuição numa tela. Diferente do Scroll que é vertical, o *Heatmap Tracking* consiste em apanhar `Target` físicos da página sem quebrar formulários e linkáveis normais, os convertendo numa metrificação de UX (`X e Y` e elemento que ele pensou que teria uma função ativável por clique). 

Como captar a exata posição percentual onde o lead repousou o dedo ou cursor em todas as rotas (Site principal de Vendas e posteriormente Painel do Lead)? 

---

## Onde começa

1. Temos páginas web renderizadas sob React Router Dom com wrappers básicos.
2. Não temos nenhuma propriedade mapeadora atachada à estrutura React que obedeça uma conversão percentual relativa ao total contido no Viewport principal. 
3. Hoje o aplicativo não tem noção sobre se "X imagem enganou um usuário" tentando ser clicada.

## Onde termina

1. Um `Higher-Order Component (HOC)` ou `Tracker Provider` Global embalando as rotas da landing page e vitrine que precisa de reestruturação térmica.
2. Captura inteligente rodando livre de atrito assíncrono (sem chamadas isoladas e espancadoras). Formação da matriz visual da UX.
3. Componente salvaguardado no React garantindo que em ambientes estreitos (Mobile vs Ultra-Wides), a percentagem seja matemática (Ex: "Aos 30% Horizontal e 10% Vertical", permitindo plotagem limpa posterior e convergente para Admin).

---

## Fluxo

```
FRONTEND
└─> Listener `<HeatmapTracker>` envelopa `<App />` ou LPs do site
    └─> Ouve universalmente `e.clientX` / `e.clientY` ao momento que evento do mouse `onClick` (ou "OnTouch") ocorre.
        └─> Processa matematicamente o local perante o Height global total documentado.
            └─> Diferencia através do `e.target.tagName`: Se foi um (Button, A) marca como "Action_Click", Senão (IMG, DIV, P) = "Dumb_Click"
                └─> Enfileira as métricas com Destino, Rota Atual da Navegação em um buffer `[..., {...}]` 
```

---

## O que precisa ser feito

### O Tracker Dinâmico - React

1. **Implementar Hook Global ou Provider Wrapper:** A criação tática do `<SessionBehaviorTracker>`. Essa casca ficará fora do escopo de re-renderização pesado. Usaremos `document.addEventListener('click')`.
2. **Sistema de Escala Absoluta (A Relação Viewport vs Full Document):** Não capturar posições em "Pixels Inteiros", do contrário num celular de `400px` clicar nos botões inferiores de navegação não será agrupado aos cliques inferiores de uma navegação na tela de `1920x1080`.
   - A fórmula clássica de Heatmap é registrar o scrollHeight / scrollWidth ou o simples Relativo `e.clientX / window.innerWidth * 100`. (Uma abstração normalizadora precisará ser pensada e escrita para não criar falsos positivos ao reconstruí-los na Fase Administrativa).
3. **Agrupamento & Batimento (Batching Local):** Nunca disparar. Sob nenhuma hipótese de click, postar o Tracking individual na arquitetura `TrackedEvent`. Crie a variável em ref local do Tracker que estocará o Log até que ele alcance tamanho `batchSize = 20` ou perante `Unload`.
4. **Resolução Semântica das Rotas:** Encartar juntamente com a coord. do ping, a string da `window.location.pathname`. "Saber onde o click se deu" será responsável por filtrar a reconstrução via React da aba do Heatmap (Tarefa 040.6).

---

## Critérios de aceite

1. Um console do navegador sem acusações de Erros ou Deprecações que impeçam um botão legitivo do FlowByte de ser clicado ou disparar formulário. 
2. Logs matemáticos locais indicando array polido gerando metadado coerente em um aparelho Desktop (aponta "CLicou 50%, 50% = Meio e Meio)") após dar clicks sobre a "Logomarca" da marca na página Vendas de captura. 

---

## Dependências

Esse motor do React FrontEnd é dependente direto da infra-estrutura unificada na Tarefa 2, e precisará obrigatoriamente aguardar a finalização da sua rota par (Tarefa 040.4 API de Recebimento de Lotes Massiva por POST Batch Payload), para conseguir se descarregar.

## Próxima tarefa → Tarefa 040.4
- Endpoint de Ingestão Desagrupadora (O Processador Ligeiro no Backend de Tracking via Batches massivos).

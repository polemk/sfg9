# Tarefa 4.3: Mobile Responsive Layout & Toggle

**Sprint:** 4 - Agent UI Redesign & Embedded Navigation
**Estimativa:** 1.5 dias
**Tipo:** Frontend

---

## Contexto
O layout Desktop `Side-by-Side` (Tarefa 4.2) é ideal para telas grandes, mas no Mobile (telas `< 1024px`) a área é muito menor. Inicialmente, a interface foi desenhada como 60% agente chat e 40% navegação do site superior, mas isso cria conflitos quando o usuário tenta navegar pelo portfólio.
A solução é um layout dinâmico e híbrido:
1. Quando o lead rolar a página para baixo (Site Mode), o chat minimiza de forma nativa para ele ler o conteúdo em tela cheia.
2. Quando ele interagir/clicar no chat (AI Mode) ou através de botões "Saiba Mais", o Agente preenche todo o espaço (Full Screen Mobile Chat). 
3. O Header superior deverá portar um Switch/Toggle ("Site Mode <> AI Mode") permitindo o controle explícito dessa alternância.

---

## Onde começa
O Mobile usa o bolotinha de chat flutuante, que quando clicado abre numa Modal fixa de chat cobrindo todo o site, não permitindo uma real transição fluída "Site <> Experiência AI", mas sim uma justaposição intrusiva.

## Onde termina
A versão Mobile da `HomePage` terá o Switch nativo em seu Topbar e o Chat de forma perfeitamente integrada no painel inferior. Se ele faz scroll natural, o chat some (Minimiza num header inferior fino). Se ele clica no topo, o chat engole a View de Venda. Interatividade absoluta, retendo e guiando o usuário no funil.

---

## O que precisa ser feito

### No Frontend

1. **TopBar Switcher**:
   Adicionar um Segmented Control ou Toggle moderno (`Site | AI`) no `Topbar` / Header Publico.
   Criar um estado no React `useResponsiveLayout({ viewMode: 'site' | 'ai' })`.

2. **Mobile Layout Container**:
   A principal Wrapper Div (`div flex-col h-screen`) deverá obedecer ao state:
   - Se `viewMode === 'site'`: A div contendo as Landing Pages exibe a página em tela cheia via `overflow-y-auto`. O Chat (Componente Bottom) fica restrito a uns `48px` ou `60px` na base contendo o hint input simulado ("Pergunte algo...").
   - Se usuario fizer o gesto de scroll down (`onScroll` events threshold > 50px de delta) garantir essa contração.

3. **Expand do Agent (AI Mode)**:
   - Se for clicado no toggle, num CTA de conteúdo, ou puxar o swipe bottom, `setMode('ai')`.
   - O chat de IA preenche a tela num BottomSheet cobrindo o background (drawer transition `translate-y-0`) contendo todo o histórico de conversa.
   - Preservar o histórico (evitar que desmontar o componente de chat faça ele reiniciar o socket inteiro ActionCable). Use o CSS `.d-none` ou Flex hiding em vez de condicional real ReactDOM remouting (`{mode === 'ai' && <Widget/>}`) caso perceba bugs de re-conexão.

### No Backend
Não se aplica, focado 100% no Fluxo React responsivo `px/height`.

---

## Observações importantes
- Teste a física de Safari/iOS e Chrome Android com atenção nos bounds da tela de rolagem. Modais que usam `100vh` geralmente ficam presas abaixo da searchbar (Endereço do navegador do mobile). Ao invés disso, prefira a técnica `h-[-webkit-fill-available]` e o safe-area do tailwindcss (`pt-safe pb-safe`).
- Animações usando Framer Motion dão aquele toque "Appnativo", recomendo para os Swipes transicionais.

---

## Critérios de aceite
Para considerar esta tarefa concluída, o dev deve demonstrar:

1. Acessando via DevTools Mobile Viewport.
2. Scroll no conteúdo longo Esconde suavemente a caixa superior do chatbot. Fica só o "Pergunte algo" bottom fixed tab bar.
3. Apertar em algo ativa o Toggle de cima, mudando pra "AI" visualmente, e a tela do Chat assume o full height sobrepondo o site.
4. Animação a 60fps sem engasgos com Framer Motion ou nativa CSS no slide-up. E que o Agente do Chat correto permaneça de pé após essas minimizadas de tela.

---

## Dependências
- Backend (Toda a Tarefa 4.1 e Frontend 4.2).

## Próxima tarefa
Revisão Geral e Demo Final.

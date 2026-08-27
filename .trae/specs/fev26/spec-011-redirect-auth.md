# Tarefa 1.2: End Node - Redirect & Account Creation

**Sprint:** 1 - Flow Connections & User Continuity
**Estimativa:** 1.5 dias(s)
**Tipo:** Backend + Frontend

---

## Contexto
O objetivo final de muitos assistentes de vendas ou suporte é converter o visitante em um lead/usuário registrado, direcionando-o para uma transação real. Precisamos de um nó que finalize a conversa e direcione o usuário para fora do widget do chat (ex: Dashboard, Página de Login, Link Externo de Checkout Pagar.me/Stripe) mantendo o roteamento sem fricção. Mais além, caso o site já saiba o nome e email do lead, queremos criar uma conta "shadow" (autologin), minimizando cliques para autenticação.

---

## Onde começa
- O Widget de chat funciona unicamente através de troca de mensagens. Não interage com o roteador da aplicação hospedeira.
- Criar contas requer preenchimento de senhas e processos longos.

## Onde termina
- O Widget de chat pode despachar eventos que comandam o navegador do hospedeiro (`router.push`) a mudar a URL ativa ou navegar externamente.
- O fluxo de autenticação pode criar um Token de Login diretamente no fim da conversa e logar o usuário automaticamente com seus dados de sessão (`Custom Variables`).

---

## O que precisa ser feito

### No Backend
- **Novo Nó:** `Ai::Nodes::Redirect` com payload `{ type: "redirect", url: "/dashboard", action: "navigate" | "scroll_to", target: "#id", auto_auth: true/false }`.
- **Ação de Auth (Shadow Account):**
  - Se a flag `auto_auth` estiver ativa:
  - Verificar no DB (buscando email via contexto do chat). Se existir, gerar e retornar um Auth Token válido (ex. via JWT) na resposta.
  - Se não existir, instanciar um `User` (Account) preenchendo Email e Nome via `session.context`. Se falhar por falta de dados, logar sem travar.

### No Frontend
- **Widget Listener:** O `AIChatWidget` ou seu hook `useChatFlow` precisa escutar mensagens de tipo `event` ou payload customizado.
  - Se ação for `navigate`: Usar hooks do React Router para transição SPA (`router.push(url)`). Em URLs externas (`http`), usar `window.location.href`.
  - Se ação for `scroll_to`: Realizar um `document.getElementById(target).scrollIntoView({ behavior: 'smooth' })`.
  - Se retornar `auth_token`: Setar o token no estado local (ex. Zustand/LocalStorage) acionando a autenticação do site antes de redirecionar.
- **Builder UI:** Atualizar a interface do painel do criador de fluxos com o bloco de "Redirecionamento / Finalizar". Oferecer checkboxes (Account Creation).

---

## Observações importantes
- **UX de Transição:** Assegure um leve `delay` natural entre a última mensagem visual no chat (ex. "Perfeito, vou te enviar pro Dashboard") e o real redirecionamento de tela (cerca de 1.5s). Caso contrário, a sensação será muito abrupta e o usuário pode não entender.
- Para a criação da conta, senhas aleatórias temporárias podem ser usadas no backend. Posteriormente, notifique o `User` por email com um Reset Password link.

---

## Critérios de aceite
1. O criador adiciona o nó "Redirect to /dashboard" ativando "Auto Account Creation".
2. O usuário na ponta testa o bote, passa seu nome e e-mail e atinge o fim do fluxo.
3. Como dev observador, você deve visualizar o payload ser recebido contendo uma nova key JWT.
4. O Widget deve setar a autenticação na aplicação e transicionar para `/dashboard` logado, renderizando a visão privada.
5. Inspecionar o banco de dados confirma que o `User` existe.
6. Testar também ancoragem, enviando `#pricing`, que deve engatilhar scroll automático para a tabela de preços do site.

---

## Dependências
- `Ai::Nodes::Handoff` ou `FlowEngine` atualizado para aceitar diferentes nós de fim de linha.

## Próxima tarefa
- Tarefa 2.1: Save to Lead Node

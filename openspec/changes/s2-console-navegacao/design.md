# Design: S2 — Console e navegação

> **Este documento não repete o mapa.** As 100 linhas item-a-item estão em
> `.migration-ai9/map/auth-admin.md` §2.5 (BE-390…BE-429), §2.6 (FE-390…FE-410), §2.8
> (DB-390…DB-399), §2.9 (OPS-390…OPS-399), §2.11–§2.14 (`feedback19`, `navkit`) e nas
> decisões **DC-11, DC-12, DC-14, DC-15, DC-16, DC-17, DC-18, DC-20**.

## 1. O roteamento: o que substitui o quê

| Peça legada | Substituto ai9 | Por quê |
| ----------- | -------------- | ------- |
| Rota-mestra `resource/topic/section` com `topic` polimórfico | ~38 rotas React com URL estável | Deep-link e histórico reais (D-92, IMP-A11) |
| `@view_path = "parts/#{id}/body"` (string interpolada, `MissingTemplate` → 500) | import estático por rota | Rota que não existe vira **404**, não 500 |
| `dashHolder` (objeto global em memória, única fonte de verdade do roteamento) | estado do roteador + React Query | Não tem equivalente e **não deve ter** |
| `replaceState` | histórico do navegador de verdade | O botão Voltar deixa de sair do console |
| `respond_to` de duas caras (`format.html` → casca, `format.js` → miolo) | API JSON + cliente que renderiza | Some o contrato de renderização em duas passadas |
| Splash preto `99vw × 98vh` com **polling de 10 ms** | `Suspense` do roteador | Princípio 10 |

**A rota curinga é obrigatória e é nova.** `App.tsx:56-87` não tem rota `*`. Sem ela, área
desconhecida vira tela em branco — e o legado já tinha o vício de **rebaixar silenciosamente
para o `dash`**, o que é pior: o usuário acha que chegou.

## 2. O menu é o documento de requisitos da navegação

`create_console_menu` (`../sfg/app/helpers/application_helper.rb:100-172`) é a fonte #1 da
matriz de autorização e a especificação de fato da navegação (**D-118**). Ele vira
configuração declarativa em `frontend/src/hooks/useNavItems.ts` — arquivo que **já documenta
o ponto de extensão por papel nas linhas 27-32**.

Três regras de porte, nesta ordem de importância:

1. **`locked` é lido do item, não do grupo.** No legado a view lia `g[:locked]` do grupo, e
   por isso os 4 itens marcados **nunca ficaram travados** (D-90). Preserva-se o **efeito**
   (as telas estão em uso), corrige-se o **mecanismo**. **Nenhum dos 4 nasce marcado**
   (DEC-15.1) — quem ler só o código legado vai achar que "corrigir" é marcar os quatro;
   está escrito aqui para que não marque.
2. **O filtro é papel + participação**, avaliado com os mesmos dados que o servidor usa
   (C3 + C1). O menu esconde a **tela de administração** do catálogo, nunca o **dado** do
   catálogo (regra 4 do §0.6).
3. **O gate `projects.count > 0`** continua existindo: o console sem projeto mostra menos
   coisas, como no legado.

## 3. Aplicação dos contratos transversais

### C1 — escopo por projeto
O **seletor de projeto** da topbar (FE-393, BE-412) é a interface direta do contrato: o
projeto corrente é **estado de servidor** (`users.current_project_id` + `current_project!`),
nunca cookie. O cookie `cached_info` do legado — escrito **pelo servidor e pelo cliente**,
com codificações diferentes, 4 dias de vida e **nenhuma flag de segurança**, carregando o
tenant — **não é portado** (DB-396, OPS-392): era o **D-28**.

O seletor troca **só** entre projetos com participação, e vale a condição 2 do DC-08:
projeto inexistente e projeto sem participação respondem igual. Corrige-se também a
heurística frágil do legado, que ao não bater o cookie com o usuário selecionava a
**segunda** opção do select, sem justificativa.

### C3 — hierarquia invertida
O menu e o redirecionador por papel (FE-404) leem a mesma hierarquia do servidor. O teste
dos dois lados aqui é: o menu de um Gerente **não** traz o grupo Admin **e** traz o grupo
Cadastro; o de um Colaborador **não** traz nenhum dos dois **e** traz as telas do projeto.
Um teste que só verifique "o Colaborador não vê Admin" passa com o filtro invertido.

## 4. Não existe dashboard — e isso é uma decisão, não um esquecimento

`DC-15`. Os 3 endpoints de `dash` do legado estão **quebrados por template ausente**
(`MissingTemplate`) e o `search` calcula um período e **não consulta nada** (D-87). Não há
model, view SQL, materialized view nem job que alimente indicador (DB-399). O que vira spec
é **só o redirecionador por papel** (FE-404): OG → usuários; Admin/Gerente → projetos quando
não há projeto, recebíveis quando há; demais → minha conta quando não há projeto, resultados
quando há.

Construir um dashboard aqui seria feature nova sem paridade. Ela existe, é a `NEW-002`, e
está na **S15** — depois dos serviços de cálculo, porque dashboard bonito sobre número
errado é pior que dashboard nenhum.

## 5. `feedback19` vira código do app

`DC-12`. Ticket (`admin_messages`), thread (`message_notes`), observadores (`observers` +
`observer_contexts`). Decisões de desenho que o mapa fixa e que valem repetir porque são
armadilhas:

- Os 4 contextos e as 8 situações viram **enum string**, não tabela — e a armadilha a matar
  é que `Feedback19::State`/`Context` resolviam registros em **variáveis de classe na carga
  da classe**, sem sincronismo (OPS-507).
- A prevenção de duplicata de observador era um `SELECT COUNT` a cada save, sujeito a
  corrida: vira **índice único `(observer_id, context_id)`**.
- **Correção observável (DC-16 / Q-B16):** pedir **"Concluído"** gravava **"Fechado"**.
  O estado gravado passa a ser o pedido, e a mudança vai para o `improvements-log.md`
  porque alguém pode depender do comportamento atual.
- Nomes internos ofensivos/piada (`hadouken`/`shoryuken`) são renomeados para campos
  nomeados (FE-406).
- **Envio público (DC-20):** no legado o `POST` era efetivamente público. Se o envio anônimo
  for feature real (Q-B17), ele entra na allowlist **por rota** com throttle do
  Rack::Attack — **nunca** por brecha de formato. Default: **manter autenticado**.

## 6. Decisões que tomei nesta fatia

| # | Questão | Decisão | Razão |
| - | ------- | ------- | ----- |
| **DS2-1** | Mensagens administrativas e observadores (fatia interna S9) não têm fatia global própria em `migration-map.md` | **Absorvidas por S2** | É a única área do console que sobrou sem casa, e ela nasce **de dentro do menu**: a tela era órfã no legado porque `create_console_menu` não a listava. Migrar a casca sem ela deixaria a mesma órfã no ai9 |
| **DS2-2** | `WhatsappPage.tsx` existe mas **não está roteada** (achado §6.7 do mapa) | **Ganha rota nesta fatia**, gateada por papel administrativo | É a tela de pareamento por QR de que `EvolutionConnection.send_message` depende via `PolemkInstance.first`. Sem rota ninguém pareia, e o login por WhatsApp (DEC-14, fatia S1) **cai quando a sessão da instância expirar**. É uma dependência de S1 que só pode ser resolvida aqui |
| **DS2-3** | `NAV-001` estava na fatia interna de autorização | **Fica em S2** | O contrato (quem pode o quê) é de S0; a **configuração declarativa do menu** é navegação, e mora no mesmo arquivo que a casca |
| **DS2-4** | Google Analytics injetado no bootstrap **sem consentimento** (OPS-391, Q-B15) | **Não injetar** | Sistema interno corporativo com dado financeiro. Se for preciso medir, usa-se a camada de analytics do próprio ai9 |
| **DS2-5** | i18n: a base **tem** o runtime (`i18next`, `react-i18next`, bundles) e **não traduz nada** (DC-17) | **Não ligar i18n**; pt-BR fixo (DEC-09) | Zero componentes chamam `useTranslation`, o bundle `pt-br` tem 255 chaves de marketing de outro produto e o `LanguageSwitcher` não troca idioma. Quem vir `i18next` no `package.json` vai supor que basta traduzir strings — **não basta, e não é para fazer** |

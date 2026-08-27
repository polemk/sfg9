# Product

<!-- impeccable:product-schema 1 -->

> **Como este arquivo foi escrito.** O `init` do `impeccable` pede uma entrevista com o
> usuário (`AskUserQuestion`). **Esta sessão não tem esse mecanismo** — quem a executa é um
> agente de fatia cujo único canal com o usuário é a orquestração. Pelo teste mecânico do
> próprio `init.md` ("um mecanismo de resposta existe se há uma ferramenta de pergunta ou a
> página de decisão no seu conjunto de ferramentas"), não há; então os fatos abaixo foram
> tirados de **documento comprometido no repositório**, não inventados, e cada um traz a
> fonte. Havia duas linhas **[INFERIDO]**; o usuário respondeu a primeira em 26/08/2026 (uso
> desktop **com mobile impecável**) e ela virou fato confirmado. Resta uma.
>
> **Nada de mundo visual aqui** (é regra do `init`): paleta, tipografia e componentes ficam
> nos tokens do ai9 e em `.migration-ai9/brand-and-metadata.md`.

## Platform

web

_(Views mobile próprias e PWA instalável fazem parte do produto — `project-options.md`,
Phase 0, e DEC-100. Continuam sendo `web`: aplicação móvel envolvendo um site não muda a
linguagem de design para nativa.)_

## Users

Quatro papéis, e a escala é **menor = mais poder** (DEC-41, contrato C3):

| Papel | Nível | O que faz |
| ----- | ----: | --------- |
| **OG** | 1 | operação do fornecedor do sistema; alcança todos os projetos |
| **Admin** | 2 | administra o cliente: contas, permissões, catálogos |
| **Gerente** | 3 | opera e administra o próprio projeto; lê usuários e convida |
| **Colaborador** | 4 | opera o dia a dia; lê os catálogos globais, não os administra |

Mais um **modificador ortogonal ao papel**: `user_is_readonly` (DEC-108) — vê tudo o que o
papel alcança e **não grava nada**. Vale inclusive para Admin.

**A situação de uso, que decide quase todo o desenho:** o usuário é um operador de crédito
olhando **um projeto por vez** (contrato C1 — o projeto corrente é estado de servidor,
revalidado contra `memberships` a cada requisição). Ele passa o dia entre lançar borderô,
conferir limite antes de aprovar operação e cobrar parcela vencida.

## Product Purpose

**Safegold** é o console de **gestão de risco e recebíveis** de uma operação de crédito.
Ele responde, por projeto: quanto foi operado, quanta exposição existe hoje, quanto ainda
cabe em cada limite, e o que já venceu.

O que ele cobre (as capabilities entregues): limites e exposição de risco, operações de
risco e seus movimentos, borderôs de recebíveis com o cálculo de tarifas, operações
estruturadas e remuneração, renegociações com parcelas e pagamentos, cobranças,
disponibilidades, indicadores mensais por projeto, e a trilha de auditoria.

**Sucesso** aqui não é engajamento: é o operador confiar no número. Um valor errado na tela
de um sistema de crédito vira decisão errada de crédito.

## Positioning

Este repositório **é um produto próprio, derivado do ai9** (DEC-50, declaração do usuário:
*"esse vai ser outro app mesmo sendo derivado do ai9, tem suas regras"*). Ele não é uma
instância configurada da base: constrói **sobre** ela e pode divergir dela quando a regra do
Safegold exigir.

O que um produto vizinho não copiaria com honestidade: **o sistema legado é a fonte de
verdade do comportamento** (DEC-30). Regra, cálculo e dado são replicados **inclusive nas
divergências deliberadas** — há defeitos de rótulo do legado (o D-95, por exemplo) que estão
preservados de propósito, com golden travando, porque "consertá-los" mudaria número na tela
principal sem ninguém ter decidido isso.

## Constraints

Estas são as que mais mudam decisão futura, todas com decisão escrita atrás:

- **C1 — escopo por projeto.** Toda consulta parte do projeto corrente
  (`current_project!`), nunca `default_scope`. **Projeto inexistente e projeto sem
  participação respondem o MESMO status**, para o endpoint não virar oráculo de ids.
- **C2 — uma origem por número.** A prévia da tela, a gravação e o painel chamam **o mesmo**
  serviço de domínio. Duas implementações da mesma fórmula é o defeito D-09, e é o que o
  contrato existe para impedir.
- **Ausência ≠ zero (D-117 / DEC-70).** "Não lançado" e "lançado como zero" são estados
  diferentes e a tela tem de mostrá-los diferentes. `R$ 0,00` afirma que se operou zero.
- **Saldos negativos aparecem como estão (DEC-01).** Sinal é dado, não erro de formatação.
- **Autorização é matriz declarativa (DEC-18).** 46 recursos × 4 papéis; nenhum endpoint
  decide sozinho. No legado a autorização vivia só na view, e por isso a requisição fora da
  tela fazia tudo.
- **Nada de polling (Princípio 10).** O que precisa ser vivo assina Action Cable; não existe
  `setInterval` batendo na API — há varredura de teste garantindo.
- **Construir SOBRE a base, não refatorá-la (Princípio 6b).** Outros sistemas de clientes
  rodam no ai9. O que parece errado na base vira linha em `.migration-ai9/upstream-flags.md`;
  só se toca num componente compartilhado quando ele bloqueia de fato este app **e** a
  mudança é pequena e claramente segura para os outros.
- **Paginação é Kaminari + envelope em cabeçalho (DEC-62)**, num lugar só.

## Terminology

O vocabulário é o do domínio, em pt-BR, e não é traduzido na interface: **borderô**,
**portador**, **carteira**, **limite** (e o **teto** dele), **exposição**, **deságio**,
**renegociação**, **parcela vencida**, **disponibilidade**, **indicador**.

No código a regra é a oposta e vale sempre: **identificadores, rotas, colunas e enums em
inglês**; comentário e texto de interface em pt-BR.

## Evidence & assets

- **Marca:** Safegold. Logo e paleta canônicas em `.migration-ai9/brand-and-metadata.md`
  (fonte: `../sfg/app/definitions/SFG/theme.rb`), já aplicadas aos tokens do ai9 em claro
  **e** escuro. Acento da marca: o ouro `#FFC107`.
- **Dado de demonstração:** `backend/db/seeds/demo/` (DEC-64 / DEC-102) — 12 clientes, 28
  empresas, limites, operações, renegociações e indicadores. **É vitrine, não roda no
  cutover.** O seed do legado é o anti-exemplo: ele mesmo se declara "feito somente para
  video de aprovacao", com limite `rand(0..100_000_000)`.
- **Fora de escopo por decisão do cliente (Phase 0):** o site público do legado não é
  migrado.

## Accessibility

- **Claro e escuro são os dois modos suportados**, e a marca tem de estar correta nos dois —
  um deles quebrado é tematização reprovada, não detalhe.
- **Cor nunca é o único portador de informação.** Estado ganha ícone e rótulo junto.
- **Contraste é medido, não estimado.** Achado que muda decisão: o ouro da marca dá
  **1,63:1** sobre a superfície clara de cartão — abaixo do mínimo de 3:1 para marca de
  dado. Ele é a cor de **ação** do produto; dentro de gráfico entra `--info`. Registrado em
  `frontend/src/components/charts/chartTokens.ts` e em `UF-S15-02`.
- **Telefone é destino, não "responsivo" (DEC-100).** 390×844 é conferido renderizando; uma
  passada anterior achou 35 destinos inalcançáveis no telefone.

## Open decisions

- **CONFIRMADO pelo usuário (26/08/2026).** O uso é **majoritariamente desktop** — mas
  isso **não rebaixa o telefone**. Palavras dele: *"a minha sim é maior parte desktop,
  porém tem que ter um mobile impecável"*.

  A distinção importa porque as duas metades puxam para lados opostos, e a leitura fácil
  ("é desktop, então mobile é secundário") é **errada**: a densidade das telas se resolve
  no desktop, e no telefone ela tem que ser **repensada**, não encolhida. Já custou caro
  duas vezes — 35 destinos do console eram inalcançáveis no aparelho até a passada da
  DEC-100, e os cartões de KPI empurravam todo gráfico para fora da primeira tela até
  a fileira virar duas colunas com tipografia própria.

  **A régua:** desktop é onde o trabalho acontece; o telefone é onde ele é conferido — e
  conferir mal é pior que não conferir. Toda tela nova nasce provada em **390×844**, com
  a `browser.js --viewport=390x844`, e "cabe na tela" não é o critério: o critério é
  **ser bom de usar ali**.
- **[INFERIDO]** Não há requisito de idioma além de pt-BR. O seletor de idioma da base
  continua visível sem ter o que trocar (`UF-3`), e a DEC-52 mandou tirá-lo da interface
  deste produto — o que sugere, sem afirmar, que multilíngue não está no horizonte.

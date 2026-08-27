# Proposal: S20 — Seed de demonstração

> Fatia **S20**, criada pela **DEC-64**. Não nasce do inventário do legado: nasce de um
> **buraco entre fatias**. S18 criou os alvos vazios (`lib/tasks/demo.rake`), S14 declara
> que *"S14 o **consome**"* e S15 também consome — **ninguém preenchia**. Não aparecia em
> script de cobertura nenhum porque o seed **não tem ID de inventário**: os scripts contam
> os 1439 IDs, e o seed não é um deles.
>
> Desenho normativo: **`.migration-ai9/demo-seed-design.md`** (262 linhas). Esta proposta
> não o repete — ela decide **como** ele vira código executável antes de todas as fatias de
> domínio terem fechado.

## Why

**Sem esta fatia, as 20 irmãs entregam telas vazias na demo de 28/08.** As telas estarão
corretas, os endpoints responderão 200, e cada lista mostrará "Nenhum registro encontrado".

Mas o motivo de ser **fatia própria**, e não um pedaço de cada domínio, é aritmético:

```
Project → Company → (Carrier, limite, taxa) → borderôs → movimentos → saldo
```

Cinco fatias semeando cada uma a sua parte produzem cinco seeds que **não conversam**. O
painel de exposição mostra R$ 4,18 mi; o cliente abre a lista de borderôs, soma, e dá
R$ 3,91 mi. **Numa demo comercial isso é pior que tela vazia** — tela vazia é "ainda não
carregamos"; número que não bate é "o sistema calcula errado". O anti-exemplo está no
próprio legado (`sfg/db/seeds.rb:243-268`, marcado como
`#TODO: seed feito somente para video de aprovacao`): `"Company teste 0"`,
`rand(0..100_000_000)` de limite e `rand(0.00..100.00)` de taxa — **87% ao mês**.

## O problema de ordem, e a resposta desta fatia

A S20 depende dos models de S3..S11, que **rodam depois dela**. Hoje o banco tem 56 tabelas
e **nenhuma** de `companies`, `carriers`, `risk_controls`, `receivable_entries`,
`risk_operations`, `risk_movements`, `renegotiations`, `indicator_entries`. A DEC-64 é
explícita: *"a S20 **não pode ser a última fatia** — se ela só rodar quando tudo estiver
pronto, ela vira o gargalo da sexta."*

A resposta é separar **o que o dado é** de **onde o dado é gravado**:

1. **`Demo::Ledger` — o razão.** Ruby puro, **zero ActiveRecord**. Gera a história inteira
   (5 contrapartes, 12 clientes, 28 empresas, a matriz de limites, 24 meses de borderôs,
   operações, movimentos, saldos, renegociações, garantias e indicadores) como structs
   imutáveis, com `Random.new(20260828)`. **É aqui que a aritmética fecha**, e é aqui que
   ela é testada — hoje, sem nenhum model de domínio existir.
2. **Escritores modulares.** Um módulo por agregado, em ordem explícita de dependência.
   Cada um declara o model que exige e **pula com aviso claro** quando `defined?(Company)`
   é falso. O que existe hoje é gravado hoje; o que nascer amanhã é gravado amanhã, **sem
   uma linha de mudança no razão**.

O ganho não é só de cronograma. Um razão único é a **única** forma de a soma dos borderôs
do painel bater com os borderôs da lista: as duas telas leem números que saíram do mesmo
cálculo, não de dois sorteios independentes.

## What Changes

- **`backend/db/seeds/demo/`** — novo. `ledger.rb` (o razão) + `support/` (RNG determinístico,
  gerador de CNPJ com dígito verificador, faixas de mercado) + `writers/` (um por agregado)
  + `orchestrator.rb` (ordem, idempotência, relatório).
- **`backend/lib/tasks/demo.rake`** — os três alvos vazios de S18 passam a funcionar:
  `demo:seed`, `demo:reset`, `demo:reseed`. Ganham `demo:status` (o que está semeado e o que
  aguarda qual fatia) e `demo:ledger` (imprime a prova aritmética sem tocar no banco).
- **`backend/spec/`** — spec do razão verificando as **7 regras de coerência** de
  `demo-seed-design.md` §7, e spec de idempotência do orquestrador.
- **Limpeza dos rastros de conferência de S0** — os projetos `alpha`/`beta` e os usuários
  `s0.*@sfg.test` saem no `demo:seed` (a DEC-64 previu isso). Deixá-los faz a lista de
  clientes da demo abrir com "Projeto Alpha".

### O que esta fatia **não** faz

- **Não cria model, migration nem endpoint.** Se um model não existe, o módulo dele pula.
  Trilha: `backend/db/seeds/demo/`, `backend/lib/tasks/demo.rake`, `backend/spec/`.
- **Não semeia os catálogos globais.** As carteiras, tipos de recebível, fontes de recurso e
  tipos de movimentação são **`OPS-540`, da S3** (`db/seeds/reference/`), aplicados pelo
  deploy. O razão os **referencia por título**; se faltarem, o módulo pula.
  **Exceção declarada:** `project_guarantee_types`, que a **DEC-86** atribuiu explicitamente
  a esta fatia, semeados como **provisórios**.
- **Não roda com `db:seed`.** `db/seeds.rb` não carrega nada de `db/seeds/demo/`. No cutover
  real o seed de demo não roda — é `rake demo:seed`, e só.
- **Não substitui o ETL.** O `sfg_etl.rake` (S14) carrega dado real do legado; este seed é
  dado fictício (DEC-16 / DEC-17.1). O que ele faz por S14 é servir de **banco de ensaio**:
  o ETL é exercitado contra ele antes de ver dado de cliente.

## Impact

- **Dados**: nenhuma tabela nova, nenhuma migration, `db/schema.rb` inalterado. Escreve em
  `users`, `projects`, `memberships` e `user_permissions` hoje; nos 12 agregados de domínio
  conforme S3..S11 fecharem.
- **Backend**: nenhum arquivo de `app/` é tocado.
- **Frontend**: nada.
- **Fatias que consomem**: **S14** (banco de ensaio do ETL), **S15** (gráficos com 24 meses
  de série), e a apresentação de 28/08 inteira.

## Dependências, por módulo

| Módulo do seed | Exige | Fatia que entrega | Estado hoje |
| -------------- | ----- | ----------------- | ----------- |
| `scaffolding` | — | — | roda |
| `users` | `User`, `UserType`, `Permission` | S0 | roda |
| `projects` | `Project` | S0 | roda |
| `memberships` | `Membership` | S0 | roda |
| `guarantee_types` | `ProjectGuaranteeType` | S3 (DEC-86) | aguarda |
| `carriers` | `Carrier`, `CarrierGroup` | S3 | aguarda |
| `segments` | `Segment`, `SubSegment` | S3 | aguarda |
| `companies` | `Company` | S4 | aguarda |
| `carrier_connections` | `ProjectToCarrierConnection` | S4 | aguarda |
| `guarantees` | `ProjectGuarantee` | S4 | aguarda |
| `risk_controls` | `RiskControl`, `RiskOperationType` | S5 | aguarda |
| `receivable_entries` | `ReceivableEntry` | S6 | aguarda |
| `risk_operations` | `RiskOperation` | S7 | aguarda |
| `risk_movements` | `RiskMovement`, `RiskMovementType` | S7 | aguarda |
| `structured_operations` | `StructuredOperation` | S8 | aguarda |
| `renegotiations` | `Renegotiation`, `RenegotiationInstallment` | S9 | aguarda |
| `indicators` | `Indicator`, `IndicatorEntry` | S10 | aguarda |

**A ordem da tabela é a ordem de execução**, e é dependência real: `risk_movements` depois de
`risk_operations` porque o saldo é o acumulado dos movimentos na ordem de `sequence`.

## Riscos

1. **Nome de coluna diferente do previsto.** O razão usa nomes próprios; a tradução para
   coluna mora **só** no módulo escritor. Coluna que mudar de nome custa uma linha, não uma
   reescrita. Onde o desenho da fatia ainda está em aberto (`projects.slug` vs `smart_id`,
   `subordinated_accounts_percent` decimal vs float), o módulo escreve **o que o model
   aceitar** e registra o que puxou.
2. **Serviço de cálculo ainda não existe.** `demo-seed-design.md` §7 manda o seed **chamar o
   serviço** em vez de escrever o número final, para respeitar DEC-01 (sinal) e DEC-02
   (float). Nenhum desses serviços existe hoje. O razão calcula com **as mesmas regras**, e o
   módulo escritor chama o serviço **quando ele existir** (`respond_to?`), recalculando por
   cima. Enquanto não existir, o razão é a fonte — e a spec das 7 regras é o que garante que
   ele não desviou.
3. **Seed envelhecer.** Toda data é relativa a uma **data-base** (`Date.current`, ou
   `DEMO_SEED_BASE_DATE`). Nenhuma data literal no razão.

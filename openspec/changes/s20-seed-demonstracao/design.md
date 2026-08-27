# Design: S20 — Seed de demonstração

> O **quê** está em `.migration-ai9/demo-seed-design.md` (elenco, volumetria, série de 24
> meses, as 7 regras de coerência). Este documento decide o **como**: a arquitetura que
> permite escrever o seed **antes** de S3..S11 existirem, sem que ele precise ser reescrito
> quando elas chegarem.

## 0. A decisão central: razão separado dos escritores

```
db/seeds/demo/
├── support/
│   ├── rng.rb            # Random.new(20260828) + amostragem em faixa e com cauda
│   ├── br.rb             # CNPJ com DV (raiz do grupo + filial), razões sociais
│   └── money.rb          # arredondamento sem número redondo, IOF de crédito PJ
├── ledger.rb             # Demo::Ledger — Ruby puro, ZERO ActiveRecord
├── ledger/
│   ├── records.rb        # os Structs do razão — nomes de NEGÓCIO, não de coluna
│   ├── cast.rb           # contrapartes, clientes, empresas (dado autoral, fixo)
│   ├── controls.rb       # matriz empresa × carrier × modalidade (limite, taxa)
│   ├── timeline.rb       # 24 meses com a história do §8
│   ├── receivables.rb    # borderôs
│   ├── operations.rb     # operações, movimentos e o saldo derivado
│   └── ancillary.rb      # renegociações, garantias, indicadores
├── writers/
│   ├── base.rb           # Demo::Writers::Base — contrato comum
│   └── <um por agregado>.rb
├── orchestrator.rb       # ordem, idempotência, relatório, pulos
└── reset.rb              # apaga só o que o seed cria, pela mesma chave natural
```

**O razão não sabe que banco existe.** Ele devolve `Struct`s. Isso resolve três problemas de
uma vez:

1. **Testabilidade hoje.** As 7 regras de coerência viram spec de objeto puro. Rodam em
   milissegundos, sem `companies` existir.
2. **Coerência entre domínios.** O saldo que o painel mostra e o borderô que o produziu saem
   do **mesmo objeto**. Não há como divergirem, porque não são dois cálculos.
3. **Custo de mudança de schema.** Renomear `order` para `sequence` (DB-236) muda uma linha
   no escritor de movimentos. O razão não é tocado.

### Por que não usar factories (FactoryBot)

Factory é para teste: cada `create` é independente, e é isso que a torna boa. O seed precisa
do oposto — **dependência total** entre os registros. Uma factory de `RiskMovement` que
sorteia o valor produz exatamente o defeito que esta fatia existe para evitar.

## 1. O contrato de um escritor

```ruby
module Demo
  module Writers
    class Base
      # Models que este escritor exige. Ausente qualquer um → o módulo PULA.
      def self.requires = []

      # Fatia que entrega os models — entra na mensagem de pulo.
      def self.owner_slice = nil

      # Grava. Devolve { created:, updated:, unchanged: }.
      def call(ledger, io:) = raise NotImplementedError
    end
  end
end
```

O orquestrador percorre a lista **na ordem declarada** e, para cada escritor:

```
✔ projects            12 criados,  0 atualizados,  0 inalterados
⏭ companies           PULADO — Company não existe ainda (chega na S4)
```

**O pulo é ruidoso de propósito.** Um seed que pula em silêncio é um seed que, na véspera da
demo, "rodou sem erro" e não semeou nada.

## 2. Idempotência: chave natural, nunca `create`

Cada escritor usa `find_or_initialize_by` com uma **chave natural estável** — a mesma chave
que o razão usa como identidade. Nenhum escritor usa `create`, `create!` ou `first_or_create`
sem chave.

| Agregado | Chave natural |
| -------- | ------------- |
| `User` | `email` |
| `Project` | `slug` |
| `Membership` | `(user_id, project_id)` |
| `Carrier` | `bank_code` |
| `Company` | `(project_id, title)` — o índice único que S4 declara |
| `RiskControl` | `(company_id, carrier_id, risk_operation_type_id)` — o índice de S5 |
| `ReceivableEntry` | `(project_id, nro_bordero)` |
| `RiskOperation` | `(project_id, contract_number)` |
| `RiskMovement` | `(risk_operation_id, sequence)` |
| `Renegotiation` | `(project_id, integration_key)` |
| `RenegotiationInstallment` | `(renegotiation_id, due_date)` — o índice de S9 |
| `IndicatorEntry` | `(project_id, indicator_id, year, month)` — o índice de S10 |

Repare que **toda chave natural coincide com um índice único que a fatia dona já planejou**.
Isso não é coincidência: se o seed precisa inventar uma chave que o schema não tem, o schema
está deixando duplicata entrar por outra porta.

Consequência prática: `rake demo:seed` duas vezes seguidas produz `0 criados` na segunda
execução, e é isso que a spec de idempotência afirma.

## 3. `demo:reset` — o que ele pode apagar

`reset` apaga **só o que este seed cria**, identificado pelas mesmas chaves naturais: os
projetos cujo `slug` está na lista do razão e tudo que é escopado a eles (na ordem
**filhos primeiro**, senão a FK de `companies` derruba o reset no meio), os usuários do
elenco pelo e-mail exato, e as 5 contrapartes fictícias pelo `bank_code`. Ele **não** usa
`delete_all` de tabela sem escopo; **não** toca nos OGs da base ai9 (`vinaoxd@gmail.com` e
companhia), que não são dado de demonstração; e **não** apaga catálogo de referência —
papéis, permissões e tipos de operação são do deploy, e apagá-los num reset de ensaio é a
forma mais rápida de derrubar o sistema cinco minutos antes da demo.

`reset` também é onde os rastros de conferência de S0 saem (`alpha`, `beta`, `s0.*@sfg.test`),
autorizado pela DEC-64. O `seed` chama essa mesma limpeza no módulo `scaffolding`, porque um
"Projeto Alpha" no meio dos 12 clientes é exatamente o tipo de detalhe que denuncia ambiente
de teste na primeira tela.

## 4. Determinismo e datas

- **`Random.new(20260828)`**, um gerador por seção do razão (`rng.for(:receivables)`), não um
  global compartilhado. Gerador global compartilhado faz o borderô de dezembro mudar quando
  alguém acrescenta uma garantia em outro módulo — e aí "estava R$ 4,2 mi ontem" vira uma
  conversa ruim no meio da apresentação.
- **Data-base** = `Date.current`, sobreponível por `DEMO_SEED_BASE_DATE=2026-08-28`. Toda data
  do razão é `base_date - N.months` / `+ N.days`. **Zero data literal.**
- A série tem **24 meses**: `M-23` (o mais antigo) até `M0` (o mês da data-base, parcial).

## 5. Como a aritmética fecha — as 7 regras, e onde cada uma mora

| # (§7 do desenho) | Onde é imposta | Como é verificada |
| ----------------- | -------------- | ----------------- |
| 1. Saldo = original − liquidações + juros + encargos | `ledger/operations.rb` — o saldo **não é um campo sorteado**, é o acumulado dos movimentos na ordem de `sequence` | spec: reduz os movimentos e compara com `operation.balance` |
| 2. Nada de número redondo | `support/money.rb` — todo valor recebe centavos não-nulos | spec: nenhum valor `% 1000 == 0` |
| 3. Faixas de mercado | `ledger/cast.rb` — cada carrier tem faixa própria de taxa e limite | spec: taxa a.m. entre 1,0% e 3,5%, e nenhuma operação a mais de 0,15 p.p. do seu controle |
| 4. Distribuição com cauda | `ledger/cast.rb` — 4 perfis de cliente, volume por perfil | spec: razão entre o maior e o menor volume mensal ≥ 10 |
| 5. História no tempo | `ledger/timeline.rb` — sazonalidade dez/jan, entrada do Aurora no M-15, crescimento | spec: todo dezembro abaixo da média mensal; M0 > M-23; o recém-entrante com ≤ 3 meses |
| 6. Estados misturados | `ledger/operations.rb` — ~70% encerradas, ~25% vivas, ~5% vencidas | spec: as três classes têm população > 0 |
| 7. Volume que pagina | volumetria do §6 do desenho | spec: `projects.size > 10` (Kaminari com 10/página → 2 páginas) |

E as regras de fechamento entre domínios, que são as que a DEC-64 cita:

| Invariante | Fórmula |
| ---------- | ------- |
| Borderô | `vlr_bruto_final = valor_bruto − vlr_bruto_recusado` e `qtd_final = qtd_titulos − qtd_recusada` |
| Float | `diferenca_float = float_calculado − float_acordado` (nunca um terceiro sorteio) |
| Limite | `Σ saldo das operações vivas (empresa, carrier, modalidade) ≤ risk_controls.limite` |
| Taxa | `|operation.agreed_rate − control.taxa| ≤ 0,15 p.p.` |
| Renegociação | `total_debt = original_pending_value + additional_value`; `remaining_value = total_debt − paid_value`; `Σ parcelas = total_debt` |
| Indicador | o indicador "Volume operado" do mês **é** a soma dos borderôs daquele mês |

A última é a que amarra o painel ao borderô: **o número do gráfico não é um número novo, é
uma agregação da mesma lista que a tela de borderôs mostra.**

### IOF: a regra real, não um percentual inventado

`support/money.rb` implementa o IOF de crédito PJ como a legislação o define — **0,0082% ao
dia sobre o principal, limitado a 365 dias, mais 0,38% adicional**. Custa cinco linhas e é a
diferença entre um número que um analista de crédito reconhece e um que ele confere e
descarta.

## 6. Onde o razão cede lugar ao serviço do app

`demo-seed-design.md` §7 é explícito: *"onde o app tiver serviço próprio de cálculo, o seed
chama o serviço"*. Hoje **nenhum** desses serviços existe. O escritor faz assim:

```ruby
# Se a fatia dona já entregou o serviço de cálculo, ele manda — é o mesmo
# caminho do dado real (DEC-01: convenção de sinal; DEC-02: aritmética em float).
if defined?(::Risk::BalanceCalculator)
  ::Risk::BalanceCalculator.recalculate!(operation)
end
```

O razão continua sendo quem **decide a história** (quantos movimentos, de que tipo, em que
data); o serviço, quando existir, é quem **fecha a conta**. Se os dois discordarem, o razão
está errado — e a spec das 7 regras é onde isso aparece.

## 7. O elenco de usuários e a matriz de autorização

`demo-seed-design.md` §9 pede 6 usuários e fala em "senhas fortes e distintas". **A base ai9
não tem senha**: a autenticação é magic login por código (`Auth::MagicLoginService`). O
elenco é o mesmo; o que muda é como se entra — em desenvolvimento o `request_code` devolve o
código no corpo da resposta, e é assim que se troca de usuário ao vivo.

Papéis conforme **DEC-41** (menor = mais poder): OG=1, Admin=2, Gerente=3, Colaborador=4. O
sexto usuário recebe a permissão `user_is_readonly`, a **única** das 17 abilities do legado
que sobreviveu (DEC-18.6).

Os e-mails ficam em **`@safegold.test`** — `.test` é TLD reservado pela RFC 2606, então
nenhuma mensagem sai do ambiente. Em desenvolvimento o SMTP é real
(`config/environments/development.rb:42-44`, `raise_delivery_errors = true`): domínio
entregável de verdade no seed é uma forma de mandar e-mail para estranhos por engano.

## 8. Alternativas descartadas

| Alternativa | Por que não |
| ----------- | ----------- |
| **Cada fatia semeia o seu** (opção (d) da P-097) | É o motivo de a DEC-64 existir. Cinco seeds que não conversam. |
| **Dump SQL pronto, versionado** | Congela no schema do dia. Qualquer migration de S3..S11 o quebra, e ninguém percebe até a sexta. |
| **Bloco único, escrito quando tudo existir** | É o caminho para ele nunca rodar antes da demo. A DEC-64 proíbe explicitamente. |
| **`faker`** | Gera "Empresa 1", CNPJ sem DV e cidade dos EUA. O que dá credibilidade é dado autoral, não gerador genérico. |
| **Reusar o seed do legado** | É o anti-exemplo: taxa de 87% a.m. |

# Design: S18 — Plataforma: configuração, segredos, boot, i18n e assets

> Origem: `.migration-ai9/map/data-infra.md` §2.2 (`ops-config`), §2.7 (`BE-458`, `BE-459`),
> §2.8 (`OPS-746`). Fatia interna **S-01** do mapa de bloco.
> Nasceu do fechamento do Phase 2: 29 IDs de plataforma sem dono, porque S13 os apontava para
> S1 e S1 nunca os reivindicou.

## Context

**No legado.** A configuração é o subsistema com mais superfície de risco por linha:
`secret_key_base` versionado em texto puro; `credentials.yml.enc` sem chave; TLS desligado
por initializer; `puma.rb` com `RAILS_ENV` fixo em `development`; quatro `application.*.yml`
e cinco `database.*.yml` por plataforma de desenvolvimento; três Gemfiles, com `Gemfile` no
`.gitignore`; catálogos de i18n em dois idiomas que a UI **nunca lê**, porque é 100%
hardcoded.

**Na base ai9.** O mecanismo já é o certo: `dotenv-rails`, `.env*` no `.gitignore`, apenas
`*.example` versionados (§3.11), `bin/switch_env`, `Gemfile.lock` e `pnpm-lock.yaml`
versionados. O que falta é o **contrato**: nada obriga uma variável a existir, e a base
repete o defeito de TLS do legado em `production.rb:83` e `development.rb:58` (**C-05**).

Isso define o desenho: a maior parte é `reuse` — não porque o trabalho é pequeno, mas porque
**a maior parte do trabalho é decidir o que não portar, e registrar a prova**.

## Goals / Non-Goals

**Goals**
- Um valor, um lugar: ENV, com `.env.example` como contrato versionado.
- **Boot fail-fast**: falta segredo obrigatório, o processo não sobe.
- TLS verificado por padrão, com escape explícito por ENV.
- Um ambiente reproduzível (um Gemfile, um `database.yml`, um lock).
- CSP e headers de segurança, que não existem em lado nenhum.
- O `type_casting.rb` vira helper explícito **com teste de valor**.

**Non-Goals**
- **Não** portar Webpacker, seus loaders nem os shims de vendor.
- **Não** escolher provedor de storage de produção (Q-07).
- **Não** reescrever o mecanismo de env do ai9 (Princípio 6b): ele já está certo.
- **Não** ligar CSP em modo bloqueante de saída (Q-20).

## Decisões

### D1 — Boot fail-fast, e a lista de obrigatórios é dado

Um initializer lê a lista de variáveis obrigatórias e **levanta na inicialização** se faltar
alguma, nomeando todas as ausentes de uma vez — não a primeira.

**Por que isso e não default:** o legado escolheu o oposto (`secret_key_base` commitado para
que "sempre funcione"), e o resultado é um sistema que sobe em produção com o segredo de
desenvolvimento e **ninguém percebe** — porque nada quebra. Falhar no boot transforma um
incidente de segurança silencioso num erro de deploy barulhento.

**A armadilha conhecida:** a lista precisa valer por ambiente. Exigir `SMTP_PASSWORD` em
`test` faz a suíte parar de rodar na máquina de quem só quer testar cálculo. A lista é por
ambiente, e o `.env.example` documenta os três conjuntos.

### D2 — TLS: o padrão vira seguro, o escape vira explícito

`ENV.fetch('SMTP_OPENSSL_VERIFY_MODE', 'peer')`. Elimina o `ssl_for_win.rb` do legado **e**
corrige a mesma coisa já presente na base ai9.

**Risco alto reconhecido:** é arquivo compartilhado (Princípio 6b — construir sobre a base,
não refatorá-la). O que justifica tocar: é **uma linha**, o padrão novo é o seguro, e o
escape por ENV preserva quem depende do comportamento atual. A linha específica do SMTP é de
S13 (Q-01, adiada pelo usuário); o initializer global é daqui.

### D3 — `type_casting.rb` vira helper, não monkey patch

O legado reabre classes do Ruby para coerção booleana e de moeda. É o initializer com mais
regra de negócio do sistema — e é regra que **decide centavo**: a conversão de `"1.234,56"`.

Vira `Sfg::Coercion`, explícito, chamado por quem precisa, **com teste alimentado por valores
extraídos do legado** (contrato **C2**, que o legado não podia oferecer porque não tem
nenhum teste — D-114). Monkey patch aqui reintroduziria, na base ai9 inteira, a classe de bug
"por que este `"false"` virou `true` aqui e não ali".

O par de moeda existe **dos dois lados** (back e front), e os dois leem o mesmo conjunto de
casos de teste. Formatação divergente entre tela e gravação é o **D-09** por outra porta.

### D4 — `date_overload.rb`: sentinelas explícitas

As sentinelas de data do domínio (o "infinito" que o legado escreve em `Date`) viram
`Sfg::DateBounds::MIN` / `::MAX`. Constante nomeada aparece no diff e no grep; monkey patch
em `Date` não aparece em nenhum dos dois.

### D5 — CSP nasce em `report-only`

Ligar CSP bloqueante numa base que nunca teve um quebra tela em silêncio — e o sintoma é
"um botão parou de funcionar", que ninguém liga a uma política de segurança. Nasce em
`report-only`, com prazo escrito para virar bloqueio (Q-20).

### D6 — i18n: um catálogo que é realmente lido

O legado tem os arquivos e não os usa. Portar os arquivos reproduziria o adorno. Aqui nasce
**um** catálogo `pt-BR`, e o portão é que **texto novo não entra hardcoded** — que é o único
jeito de o catálogo não voltar a ser decoração. Ele é também o destino de `gender_prefix` e
`pluralize_for` (helpers de S19), que no legado eram função e passam a ser dado.

### D7 — Assets: registrar, não portar

Os quatro IDs de pipeline são `reuse`, e o entregável é **prova**. Em particular
`lvt-doughnut.js`: é a evidência de que o legado carregava uma biblioteca de gráfico que
**nenhuma view instancia** — o achado que derrubou a premissa do DEC-10 e transformou
gráfico em feature nova (`NEW-001`, S15). Se essa prova não ficar registrada aqui, o Phase 4
vai procurar gráficos no legado.

## Risks

| Risco | Mitigação |
| ----- | --------- |
| **Alto** — `OPS-626` toca arquivo compartilhado da base | Uma linha, default seguro, escape por ENV, e a mudança registrada em `improvements-log.md` |
| **Alto** — boot fail-fast quebra ambiente de quem já roda | Lista **por ambiente** + `.env.example` completo + mensagem que nomeia **todas** as variáveis ausentes de uma vez |
| **Médio** — coerção de moeda decide centavo | Teste golden alimentado com valores do legado, exercitado **nos dois lados** (Ruby e TS) |
| **Médio** — CSP quebra tela em silêncio | Nasce em `report-only`; virar bloqueio é tarefa com prazo, não efeito colateral |
| **Baixo** — DEC-11 exige o ambiente legado de referência | Ruby 2.6.1 / Rails 6.0.3.2 fica **documentado no runbook**, não reproduzido no repositório ai9 |

## Migration Plan

1. `.env.example` completo + `database.yml` único (`sfg9_dev` / `sfg9_test`).
2. Initializer de variáveis obrigatórias (fail-fast), por ambiente.
3. TLS: `SMTP_OPENSSL_VERIFY_MODE` com default `peer`.
4. `filter_parameter_logging` + `cpf`/`cnpj`/`cpf_cnpj`.
5. `Sfg::Coercion` e `Sfg::DateBounds`, com testes de valor.
6. Catálogo `pt-BR` + portão de "sem texto hardcoded".
7. CSP `report-only` + headers.
8. `puma.rb` por ENV, `Procfile`, tarefas rake.
9. Bases de endpoint (`BE-458`, `BE-459`).
10. Registro das provas de descarte (assets, `paperclip_path`, defaults do Rails 6).

## Open Questions

- **Q-07** — provedor de storage em produção.
- **Q-20** — quando o CSP passa de `report-only` a bloqueante.
- **Q-01** — a linha de SMTP (de S13) segue adiada por decisão do usuário; o initializer
  global não depende dela.

# Runbook de plataforma — sfg9

> Criado pela fatia **S18**. É o lugar onde ficam as coisas que **não** são código:
> pendências bloqueadas por decisão externa, prazos escritos, e o que precisa
> acontecer fora deste repositório antes do cutover.
>
> Regra: item aqui ou tem **dono e data**, ou tem a pergunta que o destrava nomeada.
> Item sem nenhum dos dois é lembrete, e lembrete não sobrevive a uma sexta-feira.

> **Antes de apresentar, na raiz:** `bin/dev` — ele sobe backend, **worker do Sidekiq**
> e frontend juntos. Sem o worker, desativar um padrão de disponibilidade responde 202
> e a tela trava na frente do cliente. Confira com
> `cd backend && bundle exec rails sidekiq:health`. Detalhe e armadilha na **§4.3**.

## 1. Pendências bloqueadas por dependência externa

### Q-07 — provedor de storage em produção · **BLOQUEADO**

Não é escolha técnica desta migração: é infraestrutura do cliente.

**Estado atual (S18):** produção usa `disk_persistent` (`config/storage.yml`), apontando
para `ACTIVE_STORAGE_DISK_ROOT`, **fora** da árvore da aplicação. Alvos `amazon` e
`s3_compatible` já existem no arquivo — trocar é apontar `ACTIVE_STORAGE_SERVICE` e
preencher as ENV.

**Por que não pode ficar como está:** `Disk` dentro do release faz os anexos sumirem
**em silêncio** no primeiro deploy que troque o diretório — o registro no banco
continua lá, apontando para um blob que não existe. Serve para a demo (DEC-16, dado
fake); **não** serve para o cutover (**F-13**).

**`OPS-616` fica `blocked` no ledger enquanto isto não for respondido.** Não marcar
como concluído.

### Q-20 — quando o CSP vira bloqueante · **RESPONDIDO PELO DEC-48: já nasceu bloqueante**

Q-20 perguntava se o CSP nascia em `report-only` com prazo para virar bloqueio. O
**DEC-48** respondeu o contrário: nasce **bloqueante**, com o risco aceito
conscientemente. Não há prazo a agendar — há uma varredura a repetir.

**Obrigação permanente que isto cria:** toda vez que uma tela passar a carregar recurso
externo novo (mapa, gráfico, fonte, iframe, CDN), **a varredura de console tem de rodar
de novo, em light e dark**. `tsc` limpo e `rspec` verde não pegam recurso bloqueado por
CSP — o sintoma é "um botão parou de funcionar", que ninguém liga a uma política de
segurança.

Como rodar a varredura está na seção 4.

### Q-01 — `openssl_verify_mode` da linha específica do SMTP · **ADIADO POR DECISÃO DO USUÁRIO**

O initializer global (`OPS-626`) foi feito em S18: `SMTP_OPENSSL_VERIFY_MODE` com
default `peer`, nos dois `config/environments`. A configuração de SMTP em si é de
**S13**.

## 2. Ações externas obrigatórias antes do cutover

Nenhuma delas é código deste repositório. Todas são do usuário/cliente.

| # | Ação | Por quê |
| - | ---- | ------- |
| 1 | **Rotacionar o token da ReceitaWS** | O valor real está versionado no legado (`config/application.arch.yml:12`). Quem tem o repositório tem o token, e ele é **pago por consulta** (DEC-46) |
| 2 | **Rotacionar a chave do Google Maps** e restringi-la por referrer/IP | Hardcoded e duplicada em `SFG/metadata.rb:8,9` — a segunda dentro da própria URL, que vai para o HTML. Chave que vai para o navegador é pública por construção; a restrição por referrer é a única proteção real |
| 3 | **Rotacionar o `secret_key_base`** | Texto puro em `config/development_credentials.yml:1`. Quem tem o repositório **forja sessão** |
| 4 | **Rotacionar a chave privada DKIM** e **escolher quem assina** | DEC-30 / P-106 · **S1, tarefa 6.8 (OPS-501); Q-89 / Q-B19.** No legado a aplicação assinava e **a chave privada está versionada** — conferido: um `git ls-files lib/` filtrado por `dkim` devolve `lib/dkim_private_key.pem` (**D-85**). Ela está exposta a quem tiver o repositório e tem de ser rotacionada **de qualquer forma**. A S13 (OPS-485/OPS-608) já entregou o mecanismo do lado da aplicação — `Sfg::DkimSigner` + `Sfg::DkimInterceptor`, com `DKIM_DOMAIN`/`DKIM_SELECTOR` e a chave em `DKIM_PRIVATE_KEY` **ou** num `Credential` de provedor `dkim` (encriptado, DEC-61) — e ele nasce **inerte**: sem `DKIM_DOMAIN` não assina nada. **Faltam duas decisões, nesta ordem:** (i) quem assina — o **provedor de envio** (default declarado do Q-89, e aí basta deixar `DKIM_DOMAIN` vazio e publicar o `CNAME`/`TXT` que o provedor der) ou a **aplicação** (aí `DKIM_DOMAIN=safegold.com.br`, seletor novo, chave nova por ENV/Credential); (ii) **revogar no DNS o seletor `dk` antigo** — enquanto ele estiver publicado, quem tem o repositório assina e-mail em nome do domínio |
| 5 | **Gerar chaves próprias de Active Record Encryption** (`bin/rails db:encryption:init`) | As três da base vinham commitadas como default. É a cifra que protege `Credential#api_key`, onde o DEC-61 põe as chaves de terceiro |
| 6 | **Decidir se o Google Analytics é ligado** | Sistema interno com dado financeiro mandando telemetria a terceiro é decisão do cliente (DEC-87). Se ligar: `VITE_GA_ENABLED=true`, `VITE_GA_MEASUREMENT_ID`, liberar o domínio em `frontend/csp.config.ts` **e** construir a interface de consentimento (ver seção 3) |

## 2b. Avisos que precisam chegar às PESSOAS antes da apresentação (S1, tarefa 10.5)

Não é código, e é o tipo de item que some se não estiver escrito num lugar de operação.

| # | Aviso | Por quê |
| - | ----- | ------- |
| 1 | **Quem entra hoje digitando senha vai digitar um CÓDIGO.** Na tela de login a pessoa informa e-mail **ou** WhatsApp, recebe 6 dígitos com 5 minutos de validade e entra. Não há campo de senha, não há "esqueci minha senha" e não há "trocar senha" | É a **maior mudança observável** da migração inteira (DC-01 / **IMP-A1**, DEC-14). Descoberta ao vivo, na frente do cliente, parece defeito. Combinada antes, é o recurso |
| 2 | **Não existe mais auto-cadastro.** Conta nova só por **convite**, emitido por quem tem permissão; o convite chega por e-mail com um link de primeiro acesso de uso único, e **sem senha nenhuma** | DEC-18.7 / DEC-49 / D-38. No legado qualquer pessoa da internet se cadastrava até hierarquia 998 (**D-39**) |
| 3 | **Quem só sabe o próprio `username` continua entrando** — mas o código sai por e-mail ou WhatsApp | DEC-45. `username` **identifica**, não recebe. Conta com `username` e **sem** e-mail e **sem** telefone não consegue entrar: esse caso tem de ser contado no dry-run e resolvido antes do cutover |
| 4 | **Bloquear uma conta derruba a sessão aberta dela na hora**, e a pessoa vê o motivo na tela de login | DEC-39 / IMP-A15/A16/A17. No legado o bloqueio só valia no próximo login |
| 5 | **"Ver como" (impersonação) pede motivo, expira em 1 hora e fica na trilha** com o nome de quem iniciou | DEC-18.3. Quem for demonstrar precisa saber que o texto digitado ali é registro permanente |

## 3. Pendências de código declaradas, com dono

| Pendência | Dono | Nota |
| --------- | ---- | ---- |
| Interface de consentimento do GA4 | fatia de front, quando/se o GA for ligado | O mecanismo existe (`frontend/public/analytics-ga4.js`, Consent Mode v2 negando tudo). Falta quem chame `window.sfgAnalytics.grantConsent()`. Enquanto não existir, nada é coletado — que é o comportamento correto para quem está desligado |
| Consumo de `GET /api/v1/runtime_config` pelo front | fatia que constrói o mapa (OPS-482) | O endpoint devolve `{ google_maps: { api_key, enabled } }`. O `enabled: false` existe para o front distinguir "sem chave" de "chave errada" — no legado o autocomplete simplesmente não reagia, sem mensagem |
| Extensão `unaccent` no PostgreSQL | fatia que implementar busca sem acento | `db/schema.rb` só habilita `plpgsql` e `pgcrypto`. `ILIKE` já é nativo e usado; `unaccent` (DEC-05) exige uma migration |
| `Procfile` de produção | quando o alvo de deploy for definido | `config.ru`, `Rakefile` e `bin/` da base foram conferidos e mantidos. Sem saber se é systemd, container ou PaaS, um `Procfile` seria adivinhação versionada |
| 6 endpoints chamam `authenticate_user!` localmente | — | Redundante, não é um segundo gate: lê o `env['api.current_user']` que `Api::Root` já preencheu, e o 401 já saiu antes. Registrado para não ser confundido com gate duplicado |
| `backend/config/credentials_by_environment.rb` | — | Arquivo da base ai9 que não é lido por nada. Candidato a remoção no split (DEC-50) |
| `Mysql2::Error` em 4 `rescue_from` | — | Herança da base num app PostgreSQL. Inerte |
| CORS expõe só `X-Total-Count` dos quatro cabeçalhos de paginação | fatia de plataforma (S18) | `config/initializers/cors.rb:10` tem `expose: %w[X-Total-Count Link Content-Disposition]`. O DEC-62 declara o envelope em **quatro** cabeçalhos (`X-Total-Count`, `X-Page`, `X-Per-Page`, `X-Total-Pages`), e em produção — front noutro host — o navegador esconde os três que não estão na lista. **Hoje não há defeito visível**: `lib/api/pagination.ts#readPageMeta` deriva `page`/`perPage` do pedido e `totalPages` de `total/perPage`, então o resultado é o mesmo. Fica registrado porque a redundância só protege enquanto alguém souber que ela existe. Medido em dev (proxy do Vite, mesma origem): os quatro chegam |
| Linter de literal de UI no servidor | quando houver texto de servidor suficiente | Ver a regra abaixo |

### Regra de revisão — texto de servidor não entra hardcoded (OPS-629, tarefa 6.2)

**Em revisão de código, mensagem que o usuário lê e que sai do servidor tem de vir de
`backend/config/locales/pt-BR.yml`.** Vale para erro de validação, mensagem de
autorização e corpo de e-mail; **não** vale para log, que é para quem opera.

Por que a regra é escrita e não um linter de CI: o backend hoje tem **zero** chamadas a
`I18n.t` fora do catálogo do Grape. Um linter de literal apontaria o app inteiro e seria
desligado na primeira semana. Ele faz sentido quando houver texto de servidor suficiente
para ter alvo — e aí a regra já estará escrita, que é a parte que costuma faltar.

## 4. Procedimentos

### 4.1 Varredura de console com o CSP ligado (obrigatória — DEC-48)

Pré-requisitos: backend em `:3000`, frontend em `:5173`, um usuário no banco.

O que a varredura faz, e por que cada parte importa:
- escuta `securitypolicyviolation` — **é o único evento que denuncia recurso bloqueado
  por CSP**; ele não vira `console.error` em todos os casos e não vira `requestfailed`;
- roda em **light e dark**, porque tema troca imagem, fonte e SVG;
- confere que as fontes do Google **carregaram de fato** (`document.fonts`), porque
  `font-src`/`style-src` mal configurados derrubam a tipografia sem uma linha de erro;
- cunha o código de login direto no banco, em vez de usar `request_code`, para não
  esbarrar no limite de reenvio.

O script é versionado: **`frontend/scripts/csp-console-sweep.mjs`**.

```
cd frontend && node scripts/csp-console-sweep.mjs
```

Sai com código diferente de zero se houver violação de CSP, erro de página ou falha de
navegação — então serve como portão, não só como relatório. As duas dependências que não
vivem no repositório (o `playwright-core` e o binário do Chromium) são parametrizáveis
por `PLAYWRIGHT_CORE` e `CHROME_PATH`.

Resultado registrado em 25/08/2026: **10 rotas × 2 temas, 0 violações**; Work Sans em
todas as rotas e Fira Mono nas que têm número, as duas vindas de `fonts.gstatic.com`;
WebSocket do Action Cable **aberto**. Os 66 avisos que sobram são pré-existentes e não
são da plataforma (promo do i18next e *future flags* do React Router).

### 4.2 Conferir que o agendamento carregou

```
redis-cli -n 0 smembers cron_jobs:default
redis-cli -n 0 hmget cron_job:default:cleanup_login_codes klass cron source
```

Esperado: os quatro crons declarados em `backend/config/schedule.yml`
(`cleanup_login_codes`, `purge_login_attempts`, `purge_email_logs`,
`purge_audit_versions`), todos com `source: schedule`.

⚠ **`cron_job:default:data_cleanup` (fila `apl9_default`) e `cron_job:apl9:data_cleanup`
são do outro app e têm de continuar lá.** `FLUSHDB`, `Sidekiq::Cron::Job.destroy_all` ou
qualquer limpeza que não filtre derruba o cron do `apl9`. O `load_from_hash!` só apaga o
que tem `source == "schedule"`; não troque essa remoção seletiva por uma varredura.

### 4.3 Subir o worker do Sidekiq — **obrigatório antes de apresentar**

**Uma linha, na raiz do repositório:**

```
bin/dev          # sobe backend (:3000) + worker do Sidekiq + frontend (:5173)
```

Só o worker, quando o backend já está de pé noutro terminal:

```
cd backend && bundle exec sidekiq -C config/sidekiq.yml
```

**Confira antes de chamar o cliente** — a checagem sai diferente de zero quando falta worker:

```
cd backend && bundle exec rails sidekiq:health
```

#### Por que esta seção existe

Medido em 26/08/2026, no banco de desenvolvimento: **`ProcessSet` = 0 para este app**.
Desativar um padrão de disponibilidade respondia **202**, travava seis nós pelo
`Availability::TemplateLock` e o job ficava na fila **para sempre** — a tela travava
na frente do cliente, e recarregar não adiantava, porque o cadeado está no banco.

**O código dos jobs está certo.** `DeactivateProjectTemplateJob` e o de propagação
foram rodados à mão: travam, reconsolidam e liberam no `ensure`. O que faltava era
**processo consumindo a fila**.

#### A armadilha, escrita porque ela engana duas vezes

`pgrep sidekiq` responde a pergunta **errada**. Vários apps dividem o mesmo Redis —
é para isso que as filas são prefixadas por `APP_NAME` (`config/sidekiq.yml`) — e no
dia da medição havia um `sidekiq` vivo na máquina apontando para **outro banco**
(`sfg9_s13_test`). `pgrep` dizia "tem worker"; o app de desenvolvimento continuava
sem nenhum. `Sidekiq::ProcessSet.size > 0` engana pelo mesmo motivo: ele é do Redis
inteiro, não deste app.

A pergunta que decide é: **cada fila deste app está na lista de algum processo vivo?**
É exatamente isso que `rails sidekiq:health` responde — ele imprime as filas do app,
os processos vivos com as filas de cada um, e nomeia as filas descobertas. Quando os
processos vivos são todos de outro app, ele diz isso com todas as letras.

⚠ **Nunca `pkill sidekiq`.** Isso derruba o worker do vizinho junto. Mate pelo PID que
você anotou ao subir o seu.

## 5. Ambiente de referência do legado (DEC-11)

**Ruby 2.6.1 / Rails 6.0.3.2** é o ambiente de **referência do legado**, e é dele que
saem os valores golden do contrato **C2**.

**Ele NÃO é reproduzido no repositório ai9** — o ai9 é Ruby 3.4 / Rails 8. O que atravessa
a fronteira são **valores**, não ambiente: `golden/coercion.json` é o exemplo do formato
— 49 casos extraídos executando o `config/initializers/type_casting.rb` do legado, lidos
pelo spec do backend e pelo cross-check do front.

Quem precisar extrair mais valores golden roda o initializer do legado isoladamente
(ele não depende da versão do Rails), não sobe o legado inteiro.

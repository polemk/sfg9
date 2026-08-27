# Flags para o time do ai9 base (NÃO corrigir nesta migração)

Princípio 6b do skill: **construímos SOBRE o ai9, não refatoramos o ai9.** Outros
sistemas de clientes rodam nessa base. O que parece errado na base vira um flag
aqui, não um refactor nesta branch. Só encostamos num componente compartilhado se
ele bloquear de fato este app **e** a mudança for pequena e claramente segura para
os outros.

| # | Achado | Onde | Por que importa | Risco de mexer aqui |
| - | ------ | ---- | --------------- | ------------------- |
| 1 | `.github/workflows/ci.yml` está **vazio (0 bytes)** | `.github/workflows/ci.yml` | O README descreve uma CI que não existe. Nenhum portão automático protege a base — nesta migração o portão de "done" passa a ser rodar build/test/lint localmente a cada slice | Baixo, mas escrever a CI da base inteira é escopo de plataforma, não desta migração |
| 2 | Versão do Ruby divergente em 3 lugares | `backend/Gemfile` (3.2.3), `.ruby-version` (3.4.9), `Dockerfile` (3.2.0) | Dev, container e CI podem rodar runtimes diferentes; bugs que só aparecem em um ambiente | Unificar afeta o build de todos os sistemas na base |
| 3 | `rescue_from :all` devolve **backtrace ao cliente** em 500 — **e transforma 405 em 500** (ver **UF-S2-01** abaixo, com a medição) | Grape root (`app/controllers/api/v1/base.rb`, `app/controllers/api/root.rb`) | Vazamento de caminho de arquivos e estrutura interna para qualquer cliente da API; e todo verbo não suportado vira erro de servidor | **CORRIGIDO NESTA BRANCH em `api/v1/base.rb`** (26/08/2026, por DEC-50 + a regra da tarefa 2.8). `api/root.rb:239-242` tem o mesmo handler e **continua como está** — não é o caminho do console. Para o ai9 o flag segue aberto nos dois |
| 4 | Gems declaradas e nunca usadas: ~~`paper_trail`~~, `aasm` (`Gemfile:45`), `groupdate`, `pg_search` (`Gemfile:87`) — ver a confirmação #S7-1 |  `backend/Gemfile` | **`paper_trail` saiu desta linha: a DEC-59 a ADOTOU** e ela é a trilha de auditoria deste produto (tabela `versions`, lista de models em `Sfg::AuditTrail::VERSIONED`). O achado continua válido para o **ai9**, que segue com a gem declarada e sem uso — e é justamente o caso de "gem sem uso significa que não há auditoria". `aasm` e `groupdate` seguem sem uso nos dois | Para o ai9: ativar auditoria é decisão de plataforma. Aqui já está ativa |
| 5 | ESLint com quase tudo `off`; `.rubocop_todo.yml` com 3051 linhas | `frontend/.eslintrc*`, `backend/.rubocop_todo.yml` | Os linters não são portão real de qualidade | Endurecer regra quebra o build de todos os sistemas |
| 7 | `RichTextInput` usa `dangerouslySetInnerHTML` **sem sanitização** e não há DOMPurify no projeto (**UF-1**, achado da S5, **confirmado e contornado pela S10**) | `frontend/src/components/RichTextInput.tsx` | Conteúdo salvo por um usuário é renderizado como HTML para os outros — XSS armazenado. A S10 é o primeiro consumidor real: a "Instrução" do indicador é HTML escrito por um usuário e **lido por todos os outros do projeto** — alcance de tenant | **A S10 NÃO tocou o componente compartilhado**, de propósito: sanitizá-lo muda o comportamento de toda tela da base que o usa. Ela promoveu um membro próprio da biblioteca, `components/ui/RichTextField.tsx`, com allowlist fechada aplicada sobre documento parseado por `DOMParser` (não regex sobre string), e **sanitiza na borda de LEITURA** — a única borda que sempre existe, porque o dado migrado do legado já está gravado e um segundo cliente grava sem passar pelo editor. Para o ai9 o flag continua aberto |
| 8 | Três stacks de rich text convivem na base (**UF-2**) | `frontend/package.json` | Três editores para o mesmo trabalho: bundle maior e três comportamentos de colar | Remover qualquer um quebra a tela que o usa |
| 9 | i18n só tem pt-BR e o seletor de idioma continua visível (**UF-3**) | `frontend/src/lib/i18n.ts` | O usuário escolhe um idioma que não existe e nada muda | É da casca compartilhada. A DEC-52 já mandou tirá-lo da interface deste produto |
| 10 | `kaminari` no `Gemfile:85` sem uma única chamada em `backend/app` (**C-07**) | `backend/Gemfile` | A gem estava declarada e a base paginava à mão, com formatos de envelope divergentes | **Resolvido NESTA migração** pela DEC-62 (Kaminari + envelope em cabeçalho). Continua flag para o ai9 |
| 6 | A regra "identificadores em inglês" já é violada na própria base | colunas `first_ad_campanha_id`, `nome_confirmado_em`; concerns `Identificavel`, `FiltravelPorOrigem`; rotas `/vendas` | Nesta migração seguimos a regra correta (inglês no código, pt-BR nos comentários) e **não replicamos** as exceções | Renomear na base é migração de dados para outros sistemas |

## Lacunas do ai9 relevantes para o Safegold (viram trabalho DESTA migração, não flag)
Estas não são defeitos da base — são coisas que a base ainda não tem e que este app
precisa. Entram no mapa de migração no Phase 2 com estratégia **build**:
- **multi-tenancy** (Safegold é multi-projeto/empresa por usuário)
- **soft delete** (domínio financeiro raramente apaga de verdade)
- **geração de PDF** (recibos e relatórios; o legado usa wicked_pdf)
- **validação de formulário no front** (sem react-hook-form/zod hoje)
- **auditoria** de alterações em registros financeiros

---

## 7. Nove tabelas orfas no `schema.rb` da base ai9 (achado no Bloco 3, 24/08/2026)

`backend/db/schema.rb` declara **9 tabelas sem model, sem migration e sem uma unica
referencia no codigo**: `work_projects`, `work_items`, `budgets` e outras seis.

**Por que isto e flag e nao tarefa desta migracao:** elas nao pertencem ao Safegold nem a
nenhuma das 35 features catalogadas. Entraram no schema **sem rastro** — nao ha migration
que as crie, o que significa que alguem editou o `schema.rb` a mao ou rodou uma migration
que depois foi apagada sem reverter. Isso e um problema da **base**, e outros sistemas de
cliente rodam sobre ela.

**Risco real:** um `db:schema:load` num ambiente novo cria as 9 tabelas vazias e ninguem
sabe de onde vieram. Se um dia alguem escrever uma migration com um desses nomes, o
comportamento fica imprevisivel.

**Nao mexer aqui** (Principio 6b: construir SOBRE o ai9, nao refatorar o ai9). Sinalizar
para quem mantem a base decidir se derruba ou se resgata o historico.

---

## 8. `current_ip` nao existe — o login por magic code responde **500** (achado no Bloco 4, 24/08/2026)

`POST /auth/v1/magic_login/request_code` devolve:

```json
{"error": "undefined local variable or method `current_ip' for Grape::Endpoint in '/auth/:version/magic_login/request_code'"}
```

**O metodo `current_ip` nao esta definido em lugar nenhum do backend.** Ele e chamado em
`app/controllers/api/auth/v1/magic_login.rb` (linhas 33, 40, 79, 85) e em
`app/controllers/api/auth/v1/oauth.rb:119`, mas nao existe `def current_ip` em
`auth_helpers.rb`, em `controller_helpers.rb` nem em nenhum outro arquivo do app.
`git log -S "def current_ip"` mostra que ele sumiu no commit `8f99059e6` ("impersonate"),
que reescreveu o `api/auth/v1/base.rb`.

**Por que a suite nunca acusou:** os dois specs que exercitam esse caminho **estubam** o
metodo — `spec/requests/api/auth/v1/magic_login_spec.rb:6` e
`spec/requests/api/auth/v1/code_validation_spec.rb:5` fazem
`allow_any_instance_of(Grape::Endpoint).to receive(:current_ip).and_return('127.0.0.1')`.
Com o stub o `rspec` passa; sem ele o endpoint real 500a.

**Estado: pre-existente**, anterior ao trim. `git grep current_ip e06be801` (fim do Bloco 3)
mostra as mesmas 5 chamadas e nenhuma definicao. Nenhum arquivo desse caminho foi tocado
pelos Blocos 1 a 4. A verificacao do Bloco 3 ("login conferido por leitura da cadeia
inteira") nao pegou porque foi feita **lendo**, nao **rodando**.

**Por que importa:** o AI9-030 (login) e uma das 8 features **mantidas**, e e o unico login
vivo do ai9. Um `def current_ip; request.ip; end` em `Api::Auth::V1::AuthHelpers` resolve —
mas o helper e compartilhado com os outros sistemas da base, entao **quem mantem o ai9
decide**, nao esta migracao (Principio 6b).

**Como foi descoberto:** rodando de verdade (`rails s` + `curl`) na verificacao do portao
"o console navega sem plan_features" do Bloco 4. O login foi contornado emitindo o refresh
token direto pelo `Auth::TokenService` — o resto da cadeia (refresh -> sessions/status ->
sessao restaurada) funciona normalmente.

---

## 8. O login por codigo esta quebrado na base ai9 — e cada migracao redescobre isso

**Sintoma:** `POST /auth/v1/magic_login/request_code` responde **500**. Quatro metodos sao
chamados no caminho de entrada e **nao existem em lugar nenhum** do backend:
`current_ip`, `current_user_agent`, `check_brute_force!` e `check_rate_limit!`
(`magic_login.rb:33,35,40,41,79,85,86`, `oauth.rb:119`). Ha um **quinto**: no callback de
OAuth, `fetch_oauth_user` estava como `private def` no corpo da classe `Grape::API`, ou
seja metodo da CLASSE e nao do `Grape::Endpoint` que roda o bloco.

**Por que ninguem viu:** os specs **estubam** os metodos ausentes
(`allow_any_instance_of(Grape::Endpoint).to receive(:current_ip)`). A suite fica 100%
verde num endpoint que estoura em producao. Vale como licao alem deste caso: **stub de
metodo inexistente transforma a suite em prova de que o teste passa, nao de que o codigo
funciona.** A verificacao do Bloco 3, feita **lendo** a cadeia de chamadas em vez de
**executar**, tambem passou — o codigo *parece* certo, todas as chamadas estao la.

**Agravante de seguranca:** o `rescue StandardError` do `request_code` devolvia
`e.message` e um campo `stage` no corpo do 500 — ou seja, entregava o nome do metodo
ausente e a etapa interna para qualquer chamador nao autenticado. Mesma familia do
`rescue_from :all` ja registrado no item 3.

**O que mais importa aqui:** isto **ja foi corrigido duas vezes**, em duas branches de
migracao diferentes, e **nunca subiu para a linha principal**:

| Commit | Branch | Mensagem |
| ------ | ------ | -------- |
| `974e53a8` | `facil/mvp`, `origin/brazilian9` | `fix(auth): restaura helpers do magic login (current_ip/brute-force/rate-limit)` |
| `38475439` | `pika9` | `mig(S1/4.27): o login por codigo volta a funcionar — os helpers que faltavam existem` |

Nenhum dos dois e ancestral do `sfg9`. Ou seja: **todo cliente novo nasce com o login
quebrado e alguem gasta horas redescobrindo o mesmo bug.** Esta e a flag mais cara da
lista, porque o custo se repete a cada migracao.

**O que fizemos aqui:** trouxemos o `38475439` por cherry-pick (o mais completo dos dois).
Um conflito, em `rack_attack.rb`, resolvido mantendo as 3 regras de autenticacao e
descartando a 4a (limite de busca de CEP — o endpoint `users/search_address` nao existe
nesta base). Verificado **executando**, nao lendo: o endpoint responde **422 "Usuario nao
encontrado"** para um e-mail inexistente, o que prova que os quatro metodos foram
atravessados e o servico executou.

**Recomendacao:** subir o `SecurityHelpers` para a `main` do ai9. Enquanto nao subir,
**toda** migracao futura comeca com a porta de entrada quebrada.


---

## 9. `LoginCode.mask_destination` não existe — o teto de envio do magic code responde **500** em vez de **429** (achado no Bloco 5, 24/08/2026)

`app/controllers/api/auth/v1/security_helpers.rb:132` chama
`LoginCode.mask_destination(destination, delivery_method)` para montar a linha de log do
teto de envio. **Esse método de classe não existe** em `app/models/login_code.rb` — os
únicos `def self.` do model são `generate_for`, `verify_code`, `cleanup_expired!`,
`cleanup_old_used!` e `normalize_destination_value`.

**Consequência:** enquanto o cliente está **abaixo** do teto, nada acontece (a linha só é
avaliada quando `count > CODE_REQUEST_LIMIT`). Ao passar de **5 pedidos em 15 minutos**
para o mesmo destino, o endpoint `POST /auth/v1/magic_login/request_code` levanta
`NoMethodError` e devolve **500**, em vez do **429** que `too_many_requests!` produziria.
Ou seja: quem bate no rate limit não recebe "aguarde alguns minutos" — recebe erro de
servidor, e o rate limit deixa de comunicar o que era para comunicar.

**Por que a suíte não pega:** o contador vive no Redis do `Rack::Attack`
(`rack_attack:...:auth/code_request:<method>:<destino>`), com janela de 15 min, e
**sobrevive entre execuções do rspec**. Com o contador frio, `spec/requests/api/auth/v1/
magic_login_spec.rb:25` passa; depois de ~6 execuções seguidas da suíte no mesmo quarto de
hora, o mesmo exemplo passa a falhar com "expected 200 but was 500" — e volta a passar
sozinho 15 minutos depois. Foi exatamente assim que apareceu aqui: a falha surgiu por
**repetir a suíte** para investigar outra intermitência, não por mudança de código.
`security_helpers.rb` e `login_code.rb` **não estão no diff de nenhum bloco do trim**.

**Mesma família da flag 8.** O cherry-pick `38475439` restaurou os helpers do
`SecurityHelpers`, mas o `LoginCode` do `sfg9` não tem o `mask_destination` que aquele
código pressupõe. É o mesmo defeito de "helper que o chamador supõe existir" — só que
agora do lado do model, e escondido atrás de uma condição que raramente dispara.

**Não corrigido aqui de propósito:** o Bloco 5 tem instrução explícita de não tocar em
autenticação (AI9-030 é feature mantida e o login acabou de ser consertado em `ab40bf83`).
A correção é de uma linha (`def self.mask_destination` no `LoginCode`, ou trocar a
interpolação por `destination`), mas pertence a quem mantém o login.

**Para quem for medir o portão do `rspec` neste repo:** se `magic_login_spec.rb:25` falhar,
limpe o contador antes de concluir que a falha é sua —
`redis-cli --scan --pattern '*code_request*' | xargs -r redis-cli del`.

### CORRECAO DE ATRIBUICAO E RESOLUCAO DA FLAG 9 (24/08/2026)

**A flag 9 nao e defeito da base — foi introduzida por MIM, no cherry-pick da flag 8.**

Antes do `ab40bf83`, o arquivo `security_helpers.rb` **nao existia** no `sfg9`. A chamada
a `LoginCode.mask_destination` entrou junto com ele. Na `pika9`, o mesmo commit trouxe
tambem o `self.mask_destination` para o `LoginCode` (`login_code.rb:223`); aqui, o
`LoginCode` so tinha o metodo de **instancia** `masked_destination`. Ou seja: portei o
consumidor sem o produtor.

**A licao, que vale para qualquer cherry-pick entre branches divergentes:** eu verifiquei
os quatro metodos que o commit **definia** e nao os que ele **chamava**. Um commit
correto na branch de origem pode depender de coisas que so existem la. A verificacao
tem de cobrir as duas pontas — e, de novo, **executando**: o `ruby -c`, o
`zeitwerk:check` e o `rspec` passaram todos, porque a linha so e avaliada **depois** de
estourar o teto.

O diagnostico do agente do Bloco 5 continua valioso e fica registrado: ele explicou por
que a falha aparecia de forma **intermitente** — o contador vive no Redis do
`Rack::Attack` com janela de 15 min e **sobrevive entre execucoes do rspec**, entao o
spec passava com o contador frio e falhava depois de ~6 rodadas no mesmo quarto de hora.

**RESOLVIDA.** `LoginCode.mask_destination` passou a existir como metodo de classe, e o
`masked_destination` de instancia delega para ela (uma regra, um lugar — mascara que
diverge e vazamento parcial). Precisa ser de classe porque o rate limit loga o destino
bloqueado **antes** de existir um `LoginCode`.

**Verificado executando:** 7 pedidos seguidos ao `request_code` — os 5 primeiros
respondem 422, o 6o e o 7o respondem **429** com "Muitas solicitacoes de codigo. Aguarde
alguns minutos". Nenhum 500.

**Aplicada tambem na `main`**, junto com a flag 8 — sem isso a `main` ficaria com o mesmo
defeito que eu acabei de introduzir nela.

---

## 10. `AssetsProxyController` — serve arquivo sem autenticacao e sem guarda de path traversal

`backend/app/controllers/assets_proxy_controller.rb:5-27` herda de `ActionController::Base`
(fora da cadeia de auth do Grape) e serve `public/uploads/**` com `disposition: 'inline'`:

```ruby
path = Rails.root.join('public', 'uploads', params[:path])
```

Dois problemas, ambos medidos por agentes diferentes do Phase 2:

1. **Sem autenticacao nenhuma.** E exatamente o padrao do **D-85/D-82** do legado, que esta
   na lista dos 23 defeitos de seguranca com veredito `corrigir` — so que dentro de casa.
2. **Sem guarda de path traversal** sobre `params[:path]`. `Rails.root.join` **nao**
   normaliza `..`.

**Decisao para esta migracao: nada do Safegold e construido sobre ele.** Documento privado
(anexo de renegociacao, por exemplo) exige entrega autenticada com URL assinada de prazo.
**Nao corrigimos aqui** (Principio 6b) — outros sistemas podem depender do comportamento
atual. Sinalizado para quem mantem a base.

## 11. `openssl_verify_mode: 'none'` **em producao**

`backend/config/environments/production.rb:82` (e `development.rb:57`) configuram o SMTP com
verificacao de certificado TLS **desligada**. Em producao isso significa que a conexao com o
servidor de e-mail aceita **qualquer** certificado — a criptografia continua, a garantia de
com quem se esta falando some. E o vetor de MITM classico.

Isto e **o D-85 do legado, ja dentro da base ai9**. Achado pelo agente de dados/infra do
Phase 2, que registrou como **Q-01**: a correcao (`ENV.fetch('SMTP_OPENSSL_VERIFY_MODE',
'peer')`) e de uma linha, mas o arquivo e **compartilhado** — se algum sistema que roda na
base usa SMTP com certificado autoassinado, ligar a verificacao quebra o envio dele.

**Precisa de decisao do usuario**, e esta na lista que vai para ele. Enquanto nao houver
aval, os requisitos **OPS-484** e **OPS-626** ficam **nao atendidos**, e isso esta
registrado — nao foi esquecido.

## 12. `Credential` so aceita provedor de IA

`backend/app/models/credential.rb:7`:
```ruby
validates :provider, inclusion: { in: %w[openai anthropic google openai_whisper] }
```

**Corrige o que eu escrevi no `ai9-base-catalog.md`:** eu disse que as chaves de terceiro do
Safegold (ReceitaWS, Google Maps) deveriam viver em `Credential`. **Nao podem**, sem alterar
esse `inclusion` — que e model compartilhado. Vao para ENV, com o segredo fora do repo.

Se um dia a base quiser ser o cofre de credencial generico, o `inclusion` precisa virar
configuracao. Sinalizado, nao corrigido.


## 13. O agendamento de jobs da base ai9 nao existe no codigo — so no Redis

Achado em 25/08/2026, investigando um erro que o usuario viu no terminal.

`grep -rI "Sidekiq::Cron\|sidekiq_cron\|cleanup_login_codes"` em `backend/` inteiro:
**zero ocorrencia**. Ainda assim havia 10 cron jobs registrados, todos com
`source: dynamic` — ou seja, cadastrados em runtime (Web UI do Sidekiq ou um `runner`
avulso) e persistidos **apenas no Redis**.

**Por que isso e um defeito da base, nao desta migracao:** o unico cron legitimo e vivo da
ai9 (`cleanup_login_codes` -> `CleanupLoginCodesJob`, que existe em
`backend/app/jobs/cleanup_login_codes_job.rb`) so roda porque uma chave sobrevive no Redis.
**Redis limpo, deploy novo ou ambiente novo = o cron simplesmente nao existe**, sem erro,
sem aviso, sem nada no repo que denuncie a falta. A limpeza de codigos de login para de
acontecer em silencio.

**O outro lado do mesmo defeito** foi o que gerou o barulho: o trim do Phase 1b apagou os
jobs do codigo, mas as definicoes ficaram no Redis re-enfileirando classes inexistentes a
cada 5 minutos — 916 jobs em retry com `NameError`, para sempre. Codigo apagado nao
desagenda nada, porque o agendamento nunca esteve no codigo.

**Correcao (upstream, nao aplicada aqui):** declarar o schedule em arquivo versionado
(`config/schedule.yml` carregado no boot via `Sidekiq::Cron::Job.load_from_hash!`), que
tambem **remove** o que nao esta declarado. Agendamento vira codigo revisavel e o ciclo
"apagou a classe, o cron ficou" deixa de ser possivel.

**Consequencia para a fatia S13 (jobs e integracoes):** todo cron do Safegold nasce
declarado em arquivo. Nenhum cron desta migracao pode ser cadastrado pela Web UI.

**Armadilha registrada:** este Redis e **compartilhado com o app `apl9`**
(`cron_job:apl9:data_cleanup` e `cron_job:default:data_cleanup` -> fila `apl9_default`).
`FLUSHDB`, ou qualquer limpeza que nao filtre por fila, **derruba o cron do outro app**.

---

## `APP_NAME` faz dois trabalhos incompatíveis (nome de exibição e prefixo das filas)

Achado em 25/08/2026 pelo `theming-brand-engineer`.

`ENV['APP_NAME']` é usada em dois papéis que não têm nada a ver um com o outro:

- **Nome de exibição**, em `app/mailers/auth_mailer.rb:22`,
  `app/services/auth/{email_service,magic_login_service,pre_register_service,
  visitor_signup_with_link_service}.rb`, `app/controllers/api/root.rb:168` e no
  layout de e-mail — aparece no assunto do e-mail, no corpo e na mensagem de WhatsApp.
- **Prefixo das filas do Sidekiq**, em `config/application.rb:42`
  (`config.active_job.queue_name_prefix`).

Consequência: **renomear o produto renomeia as filas**. Num ambiente já rodando,
trocar `APP_NAME` faz o worker passar a consumir filas novas e abandonar em
silêncio o que estiver enfileirado nas antigas.

Aqui isso não morde (implantação nova, `APP_NAME=Safegold` desde o início) e por
isso **não alteramos** o comportamento — mudar o acoplamento é mexer na base, não
na migração (Princípio 6b). Fica documentado em `backend/.env.example`.

**Correção upstream sugerida:** separar em duas variáveis — `APP_NAME` só para
exibição e `QUEUE_PREFIX` (com default estável) para a infraestrutura.

---

## `VITE_DEFAULT_THEME` não é lida por nenhum código

Achado em 25/08/2026 pelo `theming-brand-engineer` (já apontado no
`ai9-conventions.md` §5.4, registrado aqui como flag).

`frontend/.env.example` sugere `VITE_DEFAULT_THEME`, mas nenhum arquivo do
`frontend/src` lê essa variável. O tema padrão real é `'light'`, cravado em
`frontend/src/store/themeStore.ts`. Quem configurar o `.env` esperando trocar o
padrão não vai conseguir, e não recebe nenhum aviso.

Atualizamos o `.env.example` para `light` (o valor verdadeiro) com um comentário
explicando que a variável é inerte. **Não** implementamos a leitura — seria
mudança de comportamento na base do ai9, fora do escopo desta passagem.

**Correção upstream sugerida:** ou o `themeStore` lê
`import.meta.env.VITE_DEFAULT_THEME` na inicialização, ou a variável sai do
`.env.example`.

---

## `assets_proxy_controller.rb` e o logo: nenhum asset de marca passa por ele

Nota de acompanhamento do `theming-brand-engineer`, complementar ao **D-82** já
registrado. Os assets de marca do Safegold (`frontend/public/images/brand/*`)
são servidos como estático do Vite/CDN, **não** pelo `assets_proxy_controller`.
Ninguém precisa tocar naquele controller para tematizar — e ele continua sendo o
buraco de autenticação já catalogado.

## 14. Impersonação não tem trava de hierarquia — quem pode impersonar, impersona qualquer um

Achado em 25/08/2026, testando o alvo de impersonação recém-semeado.

`Auth::ImpersonateService.start` (`backend/app/services/auth/impersonate_service.rb:11-30`)
faz, nesta ordem: alvo existe? · alvo != eu? · `true_user.can_impersonate?`. **Não existe
nenhuma comparação de `hierarchy_level` entre quem impersona e o alvo.**

Verificado executando, não lendo:

| Cenário | Esperado | Real |
| ------- | -------- | ---- |
| OG impersona `client` | 200 | **200** ✅ |
| `client` impersonado lista usuários (rota só-OG) | 403 | **403** ✅ |
| `client` impersonado tenta impersonar outro | 403 | **403** ✅ |
| OG impersona **outro OG** | trava? | **200** ⚠️ |

Hoje isso é inofensivo, porque `can_impersonate?` é `og? || permissions.include?('impersonate')`
(`user_type.rb:110`) e só OG tem. **Deixa de ser inofensivo no Phase 3**, na fatia S0/S1: o
Safegold traz **Admin**, e as decisões **DEC-18.2** e **DEC-18.3** dizem que Admin só age
sobre hierarquia inferior. No minuto em que o tipo Admin receber a permissão `impersonate`
sem uma trava de nível, **um Admin impersona um OG** — e sai do outro lado com poder de OG.
É escalada de privilégio completa, por uma porta que já está aberta.

É o contrato **C3** (a escala de hierarquia é INVERTIDA entre os dois sistemas) chegando por
onde ninguém estava olhando: o mapeamento tratou C3 como assunto de tela de permissão e de
ETL, e a impersonação nunca entrou na conversa.

**Correção (upstream, não aplicada aqui):** `start` compara os níveis e recusa alvo de
hierarquia igual ou superior, com a mesma disciplina de teste que o C3 exige — **verificar
os DOIS lados**: "Admin NÃO impersona OG" **e** "Admin IMPERSONA Colaborador". Um teste que
só verifique que a trava existe passa com o sinal invertido, porque a trava existe: está
apontando para o lado errado.

**Ação para o Phase 3:** ao criar o tipo **Admin** em S0, **não** conceder `impersonate` até
a trava de nível existir.

---

## Estado das flags depois da fatia S0 (25/08/2026)

O **DEC-50** mudou a função deste arquivo: a `sfg9` vira repositório próprio, então
`upstream-flags.md` deixou de ser "coisas que eu não posso corrigir" e passou a ser
**"achados a levar para o time do ai9"**. Algumas foram corrigidas aqui porque a fatia
precisava do comportamento correto para cumprir o próprio contrato; as outras continuam
abertas **de propósito** (Princípio 6b: poder mexer não é razão para mexer).

| # | Flag | Estado depois de S0 | Onde |
| - | ---- | ------------------- | ---- |
| U1 | `assets_proxy_controller` sem sanitização de caminho | **aberta** — nada de S0 serve arquivo | — |
| U2 | `PermissionsChannel` aceita qualquer `user_id` sem comparar com o dono | **aberta**, mas **não repetida**: o `ProjectProgressChannel` criado em S0 recusa quem não participa do projeto (`current_user.member_of?`) | `app/channels/project_progress_channel.rb` |
| U3 | `ApplicationCable::Connection` nunca recusa conexão | **aberta** — o canal novo recusa na subscrição, que é a camada que S0 controla | — |
| U8 | `Rack::Attack` nunca inserido explicitamente | **aberta** (é `config/`, fatia S18) | — |
| U9 | `permissions.is_active` não honrado pelos consumidores da base (`downloads.rb:17,52`) | **corrigida no caminho novo**: `Authorization::PermissionResolver` só considera `permissions.is_active = true`, nos dois ramos (papel e usuário). `downloads.rb` **continua** sem honrar — não foi tocado | `app/services/authorization/permission_resolver.rb` |
| U14 | `TokenService` com segredo de fallback | **aberta** (fatia S18) | — |
| U15 | Access token sem `jti` | **aberta** | — |
| **#14** | **Impersonação sem trava de hierarquia** | **CORRIGIDA em S0.** Era pré-requisito do C3: no minuto em que o tipo **Admin** nasceu (DEC-41), a porta descrita na seção 14 ficou aberta de fato. `Auth::ImpersonateService.start` agora usa `Authorization::Hierarchy.can_impersonate?` (alvo estritamente inferior) e recusa encadeamento. Testado nos **dois** lados | `app/services/auth/impersonate_service.rb`, `spec/services/auth/impersonate_service_spec.rb` |

### DS0-1 — a decisão de trilha mudou entre o design de S0 e o DEC-59

O `design.md` de S0 (DS0-1) escolhia uma trilha genérica `AuditEvent`, com
`permission_audit_logs` seguindo sem produtor. **O DEC-59 revogou isso**: a trilha é o
`paper_trail`, gem que já estava em `backend/Gemfile:47` sem nenhum uso.

O resultado prático é o mesmo que DS0-1 queria — **uma trilha só** — mas sem escrever
código de trilha em cada serviço:

- **`AuditEvent` NÃO existe** e não deve ser criada por nenhuma fatia posterior;
- **`permission_audit_logs` continua sem produtor** — permanece a linha desta lista;
- a tabela é `versions`, com `object`/`object_changes` em `jsonb` e payload **completo**
  (DEC-78), mais três colunas próprias: `impersonated_id`, `reason` e `ip_address`;
- retenção finita desde o início (`PurgeAuditVersionsJob`, padrão 1825 dias,
  `AUDIT_VERSIONS_RETENTION_DAYS`). ~~Falta a linha no schedule versionado~~ —
  **RESOLVIDO**: a S18 criou `backend/config/schedule.yml` e o job está agendado às
  03:50 `America/Sao_Paulo`. Conferido pela S19.

**Models versionados (lista deliberada e curta, DEC-78 #1).** A lista deixou de ser
uma frase neste documento e virou **código verificado** (S19):

- é declarada num lugar só — `backend/app/lib/sfg/audit_trail.rb`, com **fatia dona e
  motivo escrito por linha**, e uma segunda lista, `EXCLUDED`, com o motivo de cada
  exclusão. A metade das exclusões importa tanto quanto a das inclusões: sem ela, a
  próxima pessoa lê a lista curta como esquecimento e "conserta";
- a fatia dona acrescenta a linha e escreve `include Auditable` no model
  (`app/models/concerns/auditable.rb`), que lê as opções da lista. Incluir sem
  declarar levanta na carga da classe;
- `spec/lib/sfg/audit_trail_spec.rb` reprova quatro desvios: model versionado sem
  declaração, model declarado sem versionar, opções (`skip`/`ignore`) divergentes, e
  model declarado sem verbete pt-BR.

**O portão pegou um caso real na primeira execução:** `AdminMessage`, `MessageNote` e
`Observer` (S2) tinham ganhado `has_paper_trail` sem declaração. Os três são
**atendimento** — nem auditoria financeira nem de acesso, que são os dois critérios do
DEC-78 #1 — e nada no repositório lia as versões deles. Saíram, com o motivo em
`EXCLUDED`.

Hoje: `User`, `UserType`, `Permission`, `UserPermission`, `UserTypePermission`,
`Project`, `Membership` (existentes, S0) e, **declarados antes de nascerem**,
`RiskControl` (S5), `Receivable` (S6), `RiskOperation` (S7), `StructuredOperation`
(S8), `Renegotiation` (S9) e `Contract` (S12).

## 15. `Api::V1::Chat` esta montado DUAS vezes, e uma delas fora do gate de `/api/v1/*` (achado na S2, 25/08/2026)

**O que é.** O mesmo endpoint é montado em dois lugares:

- `backend/app/controllers/api/v1/base.rb:33` — `mount Api::V1::Chat`, **dentro** de
  `Api::V1::Base`;
- `backend/app/controllers/api/root.rb:195` — `mount Api::V1::Chat # Direct mount for debugging`,
  direto na raiz.

`Api::V1::Chat` declara `prefix "chat"` por conta própria, então as duas montagens
respondem em caminhos diferentes.

**Por que é flag e não conserto desta fatia.** O `before` de `Api::V1::Base` roda
`require_not_readonly!` — o gate do modificador `user_is_readonly` (DEC-18.6). **Ele só
roda no que está montado dentro do `Base`.** A montagem "for debugging" da raiz passa por
fora dele: um usuário com concessão ativa de somente-leitura alcança o mesmo endpoint sem
o clamp, pelo outro caminho.

A montagem duplicada é da **base ai9**, não do Safegold, e o `# Direct mount for debugging`
diz que ela nasceu temporária. Remover é uma linha; o que impede fazer aqui é que o
caminho pode ter consumidor no produto de origem — é exatamente a **Regra de fronteira**
lida do lado de fora do repositório.

**Recomendação ao ai9:** remover a montagem da raiz, ou movê-la para dentro do `Base`.
Enquanto isso, qualquer gate novo que entrar no `before` do `Base` tem o mesmo furo.

## 16. `useAutoRefresh` e um helper de POLLING na base — e polling e proibido nesta migracao (achado na S2, 25/08/2026)

**O que é.** `frontend/src/hooks/useAutoRefresh.ts` é um `setInterval` de 30 s por padrão
que reexecuta uma função. É um **helper que facilita polling**, disponível a qualquer tela.

**Por que é flag.** O §5.7 das convenções desta migração é explícito: *"polling é proibido
nesta migração"* — o que atualiza sozinho atualiza por **Action Cable**. Um hook chamado
`useAutoRefresh`, exportado da pasta de hooks, é um convite a resolver "a tela precisa
atualizar" com o intervalo em vez do canal, e cada tela que o usar cria uma requisição a
cada 30 s por aba aberta.

**Estado hoje:** o hook está **sem nenhum consumidor** no repositório — nenhuma tela o
importa. Ele não é dívida ativa; é dívida **disponível**.

**Recomendação ao ai9:** remover, ou renomear para algo que anuncie o custo
(`usePollingInterval`) e documentar quando é aceitável. Neste repositório, a S2 não o
introduziu em lugar nenhum e nenhuma tela nova deve introduzir.

## 17. `GET /api/v1/users/find_by_whatsapp` **sem gate nenhum** (achado na S1, 25/08/2026 — U4)

**O que é.** `api/v1/users.rb` montava `find_by_whatsapp` fora de qualquer autorização.
Toda a rota `/api/v1/users` está atrás de `authorize!('users', …)`; **esta não estava**.

**Por que é grave aqui, e não era na base.** O serviço devolve o
`Api::Entities::User` inteiro do dono do número — nome, e-mail, CPF/CNPJ, endereço,
identificador. Qualquer sessão autenticada consultava qualquer telefone. No Safegold, o
papel mais numeroso é o **Colaborador**, que pela matriz (DEC-18) **não tem acesso
nenhum** ao recurso de contas: o endpoint era um caminho lateral para ler a base de
clientes inteira, um telefone por vez.

**O que fizemos neste repositório.** Acrescentamos `authorize!('users', :read)`, que põe
o endpoint sob a mesma matriz do resto do recurso. Teste dos dois lados em
`spec/requests/api/v1/users_account_lifecycle_spec.rb`: Colaborador recebe 403, OG
recebe 200.

**Recomendação ao ai9:** aplicar o mesmo gate. Um endpoint de busca por identificador
pessoal que devolve o registro completo precisa de autorização mesmo em produto sem
papéis — senão qualquer conta lê a base de usuários por enumeração de telefone.

## 18. `Rack::Attack.cache.store` é Redis e **não é isolado entre exemplos** (achado na S1, 25/08/2026)

**O que é.** O contador de `check_rate_limit!` vive no Redis do `rack-attack`. Redis não
participa da transação do teste: o contador **sobrevive ao rollback e à execução
inteira**.

**Por que é flag.** O sintoma é o pior possível para quem for depurar: um request spec
que pede código de acesso para o mesmo endereço passa nas primeiras execuções e **começa
a falhar a partir da sexta**, sem que nenhuma linha tenha mudado. Quem investigar vai
procurar no código do login — que está certo —, porque a causa está num contador fora do
processo. Perdemos tempo com isto nesta fatia.

**O que fizemos neste repositório.** `spec/support/rack_attack_isolation.rb` limpa o
store antes de cada exemplo, com `rescue` para que Redis fora do ar não derrube a suíte.
O teto continua exercitável de propósito: basta pedir seis vezes dentro do mesmo exemplo.

**Recomendação ao ai9:** adotar o mesmo arquivo de suporte.

## 19. `ImageCropper` estava inteiro em **inglês**, com zero consumidores (achado na S3, 25/08/2026)

**O que é.** `frontend/src/components/ui/ImageCropper.tsx` é um recortador de imagem
completo da base ai9 — e até esta fatia ele tinha **zero call sites** no repositório.
Todos os rótulos estavam em inglês: `No logo`, `Change`, `Crop Logo`, `Drag to position`,
`Cancel`, `Save`, `Uploading...`, e o `placeholder` padrão `Upload image`.

**Por que é flag.** O produto é **pt-BR fixo** (DEC-09: i18n fora de escopo, o ai9 nasce
em pt-BR como o legado) e nenhuma tela chama `useTranslation`. Um componente que só
aparece quando o usuário clica em "enviar imagem" é exatamente o tipo de coisa que
ninguém revisa até a demo — e aí o cliente abre o recortador do logo do portador e lê
"Crop Logo" no meio de um sistema de crédito em português.

**O que fizemos neste repositório.** A S3 é a **primeira consumidora** do componente
(logo do Portador, DEC-47). Traduzimos **apenas as strings**; props, assinatura e
comportamento estão intactos, e um comentário no topo do arquivo diz por quê. Risco
próximo de zero justamente por não haver outro consumidor.

**Recomendação ao ai9:** se o componente for usado em produto de outro idioma, os rótulos
precisam virar props (ou passar pelo i18n) em vez de literais. Enquanto for um produto
só, literal em pt-BR é honesto; literal em inglês num produto pt-BR não é.

## 20. `DataTable`: o cabeçalho **ordenável** perdia o versalete (achado na S3, 25/08/2026)

**O que é.** Em `frontend/src/components/ui/DataTable.tsx` a coluna ordenável renderiza o
rótulo dentro de um `<button>`. O **preflight do Tailwind** aplica
`button, select { text-transform: none }` ("removes the inheritance of text transform in
Edge and Firefox"), então o `uppercase` do `TableHead` não alcançava o rótulo: numa mesma
linha de cabeçalho, as colunas ordenáveis saíam em caixa mista e as não-ordenáveis em
versalete.

**Por que é flag.** É uma diferença que **nenhum portão pega**: `tsc` passa limpo,
`vitest` passa limpo (o texto é o mesmo; o que muda é o CSS), e o defeito só aparece com
uma listagem real na tela, misturando colunas ordenáveis e não-ordenáveis. Foi assim que
apareceu — na primeira listagem de portadores com dado de verdade.

**O que fizemos neste repositório.** `uppercase tracking-[0.05em]` explícitos na classe do
botão do cabeçalho, com o motivo no comentário. Vale para toda tela que use `DataTable`.

**Recomendação ao ai9:** qualquer rótulo que herde `text-transform` de um ancestral e
seja renderizado dentro de `<button>` precisa reaplicar a classe. O preflight não é
opcional e não avisa.

## 19. `sidekiq-cron` enfileira na fila com o prefixo **DUPLICADO** quando a entrada não declara `queue:` (achado na S13, 25/08/2026)

**Este é o item mais grave desta rodada, e é o irmão silencioso do item #13.**

**O que é.** Em `sidekiq-cron` 2.4.0, uma entrada de schedule sem `queue:` faz o gem
derivar a fila da própria classe. Para um `ActiveJob`, `klass.queue_name` já vem
**prefixada** por `config.active_job.queue_name_prefix` (`ai9_default`). O gem então
chama `klass.set(queue: "ai9_default").perform_later`, e o `set(queue:)` do ActiveJob
**aplica o prefixo de novo**. Resultado: `ai9_ai9_default`.

Essa fila **não está em `config/sidekiq.yml`**, então nenhum worker a consome. O job é
enfileirado com sucesso, não dá erro, não vai para o retry, não vai para o dead set —
ele simplesmente fica.

**O estrago medido nesta base, em 25/08/2026:**

| Classe na fila `ai9_ai9_default` | Quantidade |
| -------------------------------- | ---------- |
| `DriveIngestionJob` | 441 |
| `PublishScheduledDraftsJob` | 441 |
| `BlogIntakeSessionExpiryJob` | 221 |
| **`CleanupLoginCodesJob`** | **56** |
| **Total** | **1159** |

As três primeiras são classes apagadas pelo trim (rastro do item #13). **A quarta é
o problema atual:** `CleanupLoginCodesJob` existe, o cron dispara de hora em hora, o
job é enfileirado — e **nunca roda**. O mais recente estava enfileirado havia menos de
uma hora. A limpeza de códigos de login da base **nunca aconteceu**, nem pelos crons
dinâmicos antigos nem pelo `schedule.yml` versionado que a S18 acabou de criar.

**Por que nenhum portão pegava.** O portão de boot (`config/initializers/sidekiq_cron.rb`)
confere se a **classe agendada existe** — e ela existe. O painel do Sidekiq não acusa
fila não declarada. `rspec` e `zeitwerk:check` não têm como ver. O único sintoma é o
efeito não acontecer, que é exatamente o que ninguém procura.

**O que fizemos neste repositório.** Toda entrada de `config/schedule.yml` passa a
declarar `queue:` **sem o prefixo** (`queue: default`, não `queue: ai9_default`), e
`spec/config/schedule_queue_spec.rb` reprova: entrada sem fila, fila já prefixada, fila
ausente de `config/sidekiq.yml` e divergência com o `queue_as` da própria classe.
Verificado **executando**: com o worker no ar, os 4 crons caem em `ai9_default` /
`ai9_low_priority` e são consumidos na hora.

A fila morta foi drenada **seletivamente** (`Sidekiq::Queue#clear` só em
`ai9_ai9_default`): 1159 removidos, `apl9_default` seguiu com seus 209 jobs e
`cron_job:apl9:data_cleanup` intacto. **Nenhum `FLUSHDB`** — o Redis é compartilhado
com `apl9` e `tru`.

**Recomendação ao ai9:** declarar `queue:` em todo cron e adotar o spec. Enquanto isso
não acontecer, **qualquer job agendado da base cai numa fila que ninguém consome.**

## 20. `active_storage_attachments.record_id` é `uuid` e impede anexo em model de PK `bigint` (achado na S13, 25/08/2026)

**O que é.** A tabela nasceu com `record_id uuid NOT NULL`, porque todos os models que
a base anexava (`Medium`, `User`) têm PK `uuid`. Qualquer model com PK `bigint` que
tente `record.avatar.attach(...)` recebe:

    PG::NotNullViolation: null value in column "record_id"

O Postgres não converte o bigint para uuid, o valor chega `NULL` e a gravação estoura.

**Por que importa.** Não aparece em `zeitwerk:check`, não aparece em `tsc`, não aparece
em revisão de código — aparece **na primeira vez que alguém anexa um arquivo de
verdade**. Nesta migração isso incluiria os 4 anexos de documento financeiro da
renegociação e os logos de fornecedor e portador.

**O que fizemos neste repositório** (`db/migrate/20260825214500`): `record_id` passa a
ser `string`, que é a forma que o próprio Rails documenta para bases com chaves
primárias mistas. Dado existente é preservado — `uuid::text` mantém o mesmo literal.
Continua `string` mesmo com a padronização em uuid em curso: `record_id` não é FK de
uma tabela, é o lado solto de uma associação polimórfica.

**Efeito colateral que vale registrar**, porque morde em silêncio: com `record_id`
string, `attachment.record_id == record.id` passa a ser `"5" == 5` → `false` para todo
model bigint. Comparar com `.to_s` dos dois lados.

## 21. `config/environments/test.rb` não declara `delivery_method` — a suíte fala **SMTP de verdade** (achado na S13, 25/08/2026)

**O que é.** O arquivo declarava `action_mailer.perform_caching = false` e mais nada de
e-mail. O default do Rails para `delivery_method` é `:smtp`, e as `smtp_settings` de
`development.rb`/`production.rb` não se aplicam — o Rails tenta `localhost:25`.

**Sintoma medido:** todo exemplo que dispara um mailer trava ~7 s e morre com
`Net::OpenTimeout`. Num ambiente de CI com SMTP alcançável, a suíte **mandaria e-mail de
verdade** — inclusive código de acesso, que neste produto **é a credencial** (DEC-14).

**O que fizemos neste repositório:** `delivery_method = :test`, com
`raise_delivery_errors = true` mantido de propósito — é o que permite exercitar o
caminho de **falha** de entrega (DB-481). Sem ele o erro some e o log de falha nunca
seria testado.

**Recomendação ao ai9:** mesma linha, em qualquer produto derivado da base.

## 22. O exemplo canônico de job de `ai9-conventions.md` §3.7 é o antipadrão do D-79 (divergência consciente da S13)

**O que é.** A convenção traz como exemplo um job com
`rescue StandardError => e; Rails.logger.error(...)` **sem `raise`**. É exatamente o
formato que produziu o **D-79** no legado: a fila marca sucesso, nada é retentado, o
dead set fica vazio e o trabalho se perde sem rastro.

**O que fizemos neste repositório:** os jobs do Safegold **não seguem esse exemplo**.
`rescue` em job existe para enriquecer o log e **sempre** termina em `raise`. A regra
está escrita no `app/jobs/application_job.rb` — e não só na tarefa — porque é a decisão
que alguém "conserta" de volta por analogia com o resto do repositório.
`spec/jobs/job_discipline_spec.rb` reprova `rescue` largo sem `raise`, com uma lista
nominal de exceções justificadas (registro apagado antes da execução; tolerância a
tabela ainda inexistente; um job da base com reenfileiramento próprio limitado).

**Isto não é refatoração da base:** nenhum job existente foi reescrito. É divergência
declarada do exemplo da convenção.

## 23. Confirmação das flags de anexo que a S13 **não** corrigiu

- **F-09** — `api/v1/uploads.rb:31` valida o tipo pelo `Content-Type` **declarado pelo
  cliente** (`ct.start_with?('image/')`) e não tem limite de tamanho nenhum. Continua
  como está: é da base e outros sistemas dependem dele. O Safegold não o usa mais — a
  única exceção viva é o `chat-builder`, que é feature da própria base.
- **F-10** — `AssetsProxyController` serve arquivo de `public/uploads` **sem
  autenticação e sem guarda de path traversal**. Continua como está, pela mesma razão.
  Nenhum anexo do Safegold passa por ele; um portão de spec reprova model ou service do
  Safegold que volte a escrever em `public/uploads`.
- **F-13** — storage de produção. A S18 já tirou a produção de `:local` para
  `disk_persistent` **fora da árvore da aplicação** (`ACTIVE_STORAGE_DISK_ROOT`), com
  `amazon`/`s3_compatible` prontos. A escolha do provedor continua sendo item
  obrigatório do runbook de cutover (DEC-76), **bloqueado por dependência externa**.
- **#13** (agendamento só no Redis) — **continua aberta como flag da base**. O Safegold
  a contorna declarando o schedule em arquivo versionado, mas não a corrige para os
  outros sistemas. E veja o item **19**: contornar o #13 não bastava.

---

## 24. F-14 e C-5 — o estado dos dois editores rich text depois da S12 (25/08/2026)

**F-14 (dois editores rich text) está RESOLVIDA, não pendente.** O `proposal.md` da
S12 previa registrar a duplicidade e usar um só; a **DEC-63** foi além e **removeu o
TipTap do `package.json`**, porque o argumento original (mexer no `package.json` da
base afeta outros produtos) caiu com a **DEC-50**, que tornou a branch `sfg9` um
repositório próprio.

Situação hoje neste repositório:

- **Slate** (`frontend/src/components/RichTextEditor.tsx`) é o editor, e é o que a S12
  usa nos dois formulários que criou: versão de contrato e item de ajuda.
- **TipTap** não está declarado nem importado. Há um **teste que reprova a volta**
  (`frontend/src/app/pages/__tests__/oneRichTextEditor.test.ts`): ele varre todos os
  `.ts/.tsx/.js/.jsx` do front procurando `from '@tiptap/…'` e confere o
  `package.json`. Sem essa trava, a remoção dura até o primeiro `npm install` de quem
  "precisava de um editor".

**Para o time do ai9 base:** a flag continua **válida lá**. A base segue com os dois
declarados, e dois editores rich text no mesmo bundle é peso e ambiguidade para quem
chegar depois. A decisão de qual manter é de plataforma; aqui foi tomada.

**C-5 — correção ao `ai9-base-catalog.md`, confirmada pela S12.** O catálogo **não
menciona rich text**, e ele é reuso forte, com quatro peças vivas:

| Peça | Onde | Conferido na S12 |
| ---- | ---- | ---------------- |
| Engine | `backend/config/application.rb:12` — `require 'action_text/engine'` | ativo |
| Uso existente | `backend/app/models/user.rb` — `has_rich_text :biography` | ativo |
| Tabela | `backend/db/schema.rb` — `action_text_rich_texts` | ativa |
| Editor (front) | `RichTextEditor.tsx` (Slate) e `RichTextInput.tsx` | existem |

Consequência prática, e ela mordeu: **`action_text_rich_texts.record_id` é
`uuid NOT NULL`**. Todo model que declare `has_rich_text` precisa ter PK `uuid` — por
isso `contracts` e `help_items` nascem `id: :uuid`. É o mesmo achado da flag 20, visto
pelo lado do ActionText em vez do ActiveStorage. Quem catalogar rich text no
`ai9-base-catalog.md` deve escrever essa restrição junto, senão a próxima fatia
descobre com um `NotNullViolation` na primeira gravação.

---

## 25. `has_paper_trail` cria `attr_accessor :version` e SOMBREIA a coluna `version` (achado na S12, 25/08/2026)

**Achado real, com sintoma de banco.** `paper_trail` 17.0.0
(`lib/paper_trail/model_config.rb:229`) faz
`@model_class.send :attr_accessor, options[:version] || :version` para guardar "a
versão de que esta instância foi reificada". Num model que **tem uma coluna chamada
`version`** — que é o caso de `contracts`, e o nome vem do legado (DEC-84) — o
`attr_accessor` sombreia o atributo do ActiveRecord:

```
c.valid?                  # => true
c.version                 # => 1        (o attr_accessor)
c.read_attribute(:version) # => nil      (a coluna)
c.save!                   # => PG::NotNullViolation em "version"
```

O model **validava com o número certo** e o `INSERT` ia com `NULL`. Nenhum portão
pegaria: `rspec` só falha se houver um exemplo que grave, e a mensagem que aparece
aponta para a coluna, não para a gem.

**Correção adotada aqui:** `Sfg::AuditTrail` ganhou a chave `version_association`, e a
entrada de `Contract` declara `version_association: :reified_version`. O nome da coluna
**não** muda — ela é do legado e viaja em URL.

**Para o ai9 base:** vale como aviso para qualquer model futuro com coluna `version`,
`versions` ou `paper_trail_event`. Não é bug da base; é uma armadilha da gem que só
aparece quando os nomes colidem, e o custo de descobrir de novo é uma hora de
depuração num erro que parece de esquema.

---

## S4 — achados na base ai9 (26/08/2026)

### #S4-1 — `CatalogScreen` era genérico demais no nome e específico demais no tipo

`frontend/src/app/pages/catalogs/CatalogScreen.tsx` exigia `T extends CatalogRecord`, e
`CatalogRecord` inclui `integration_key` e `is_active` — colunas que **só os catálogos globais
têm**. O componente, porém, lê **só `id` e `title`** da linha; todo o resto sempre veio das
`columns`.

Empresa não tem chave de integração nem ativação. Forkar a tela por causa de duas colunas daria
dois comportamentos de "próxima página" e dois jeitos de dizer "nada encontrado" — que é
exatamente o que o molde existe para impedir.

**Feito aqui (não é conserto da base, é a base sendo usada):** o parâmetro passou a ser
`T extends ScreenRow` (`{ id, title }`). Nenhum call site mudou. `catalogApi` foi **exportado**
pelo mesmo motivo: os recursos escopados falam o mesmo dialeto de lista.

### #S4-2 — `MobileMenuActions` tem a lista de ações CRAVADA

`frontend/src/components/mobile/MobileMenuActions.tsx` recebe `onView`/`onEdit`/`onDelete` e
desenha exatamente esses três, com esses três rótulos, num menu suspenso de 176 px encostado na
borda direita. Serve à tela para a qual foi escrito e a mais nenhuma — e o DEC-100 pede **folha**,
não menu apertado.

**Não removido** (tem consumidor). Nasceu ao lado `MobileRowActions`, com ações **declaradas**
(rótulo, ícone, motivo de bloqueio) numa folha ancorada no rodapé, em portal.
**Para o dono da biblioteca mobile:** vale migrar os consumidores de `MobileMenuActions` e
aposentá-lo — dois padrões de ação de linha é o começo de dois padrões de tudo.

### #S4-3 — `Sfg::ReceitaWs::LookupService#valid_cnpj?` era a única validação de documento, e era privada

`backend/app/services/sfg/receita_ws/lookup_service.rb:210` tinha o dígito verificador de CNPJ
como método **privado** do serviço de integração. `User#cpf_cnpj` valida só o formato
(`/\A(?:\d{11}|\d{14})\z/`), sem dígito verificador.

**Feito aqui:** `app/lib/sfg/document.rb` passa a ser o lugar único (CPF **e** CNPJ, `digits`,
`mask`). **Não alterei o `LookupService`** — ele tem spec próprio e a duplicação é de dez linhas
de algoritmo público e estável. **Para o dono de S13/S3:** delegar
`LookupService#valid_cnpj?` para `Sfg::Document.valid_cnpj?` é uma linha, e tira a segunda
implementação. Registrado em vez de feito porque mexer num serviço de outra fatia sem
necessidade é o que a Regra de fronteira pede para não fazer.

### #S4-4 — `users.app_theme_id` continua órfã (confirmando TEM-S17-08)

Reconfirmada ao mexer em `projects`: a coluna e o índice existem, `AppTheme` não. **Não removida
aqui pelo mesmo motivo da S17** — `schema.rb` está sendo editado por outras fatias, e o
`checkpoint.md` documenta duas armadilhas de banco nesse cenário exato.

### #S4-5 — `MobileChartCard.tsx` estava com erro de type-check enquanto esta fatia rodava

Às 23h47 de 25/08 o `tsc --noEmit` acusou
`MobileChartCard.tsx(140,29): TS2322 … Formatter<string | number, string>`. O arquivo estava
sendo editado por outro agente no mesmo minuto (`git status` mostrava `M`), e o erro sumiu
sozinho em seguida. **Registrado só para que não seja atribuído à S4** — nenhum arquivo desta
fatia importa `MobileChartCard`.

### #S4-6 — ⚠ BLOQUEADOR DE SUÍTE achado às 00:15 de 26/08: duas migrations com a MESMA versão, e uma tabela criada DUAS vezes

Descoberto ao rodar o portão final da S4. **Não é da S4** — as duas fatias envolvidas são S10 e
S11 —, mas **derruba `rspec` inteiro para todo mundo**, porque
`ActiveRecord::Migration.maintain_test_schema!` roda num `before(:suite)`:

```
ActiveRecord::DuplicateMigrationVersionError:
  Multiple migrations have the version number 20260826170000.
```

**1. Colisão de versão (S10 × S11), duas vezes:**

| Versão | Arquivos |
| ------ | -------- |
| `20260826170000` | `create_availability_templates.rb` (S11) **e** `create_indicators.rb` (S10) |
| `20260826170100` | `create_availability_entries.rb` (S11) **e** `create_project_indicator_connections.rb` (S10) |

Timestamp "redondo" escrito à mão colide quando duas fatias trabalham no mesmo dia. **Sugestão:**
usar o timestamp real (`rails g migration` já faz isso) ou reservar faixas por fatia.

**2. `project_indicator_connections` é criada DUAS vezes — e o ID tem dono único.**

`DB-082` é da **S4** por decisão do fechamento do Phase 2 (a seção "Fronteiras — dono único dos
IDs em disputa", contrato **C4**): a tabela nasce em
`20260826100300_create_project_connections.rb`, junto com `project_to_carrier_connections`, e o
comentário dela **já declara** que a FK para `indicators` é acrescentada pela S10. A S10 criou a
mesma tabela em `20260826170100_create_project_indicator_connections.rb`, citando `DB-312`/`DB-586`.

**Resolução proposta, e por que nesta direção:** a migration da S10 vira
`add_foreign_key :project_indicator_connections, :indicators, column: :indicator_id` (mais o que
mais ela precisar de `indicators.scope`, DB-092). A tabela fica onde está por três motivos:
é a irmã de `project_to_carrier_connections` e as duas se leem juntas; já está aplicada no banco
de desenvolvimento; e o ID está atribuído à S4 no ledger. **Não apaguei o arquivo da S10** — ele
estava sendo escrito enquanto isto era descoberto, e apagar arquivo de outra fatia no meio da
escrita é como se perde trabalho.

**Nota de leitura para quem resolver:** as duas migrations concordam no desenho (índice único
composto, FK reais, e `is_active` **não** criada porque a coluna nunca existiu no legado apesar do
`permit`). A divergência é só de dono, não de conteúdo.

### #S4-7 — `zeitwerk:check` vermelho às 00:23 por `IndicatorEntry` (S10), não pela S4

```
Sfg::AuditTrail.options_for  (app/lib/sfg/audit_trail.rb:194)
  ← Auditable                (app/models/concerns/auditable.rb:25)
  ← IndicatorEntry           (app/models/indicator_entry.rb:35)
```

`IndicatorEntry` faz `include Auditable` **sem estar declarado** em
`Sfg::AuditTrail::VERSIONED` — que é exatamente a trava que a S19 pôs ali de propósito
(*"incluir este módulo num model que não está declarado lá levanta na carga da classe, com a
mensagem dizendo o que fazer"*). **A trava funcionou.** Fica registrado só para não ser atribuído
à S4: nenhum model desta fatia inclui `Auditable`, e a razão está escrita — `Company`,
`Provider`, `ProjectGuarantee` e `ProjectToCarrierConnection` **não** estão na lista de models
versionados, e a lista é deliberadamente curta (DEC-78 #1). `Project` e `Membership` já estavam
lá desde a S0.

**Para o dono da S10:** ou acrescentar `IndicatorEntry` a `VERSIONED` com o `why` escrito, ou
tirar o `include`. As duas metades têm de andar juntas — é o que `spec/lib/sfg/audit_trail_spec.rb`
confere.

### #S4-8 — 21 falhas de `rspec` às 00:30, todas de fatias em voo, nenhuma da S4

Snapshot do momento em que a S4 fechou. `bundle exec rspec` no repositório inteiro:
**1258 exemplos, 21 falhas**, agrupadas por arquivo:

| Arquivo | Fatia dona | Causa |
| ------- | ---------- | ----- |
| `spec/models/attachable_multiple_spec.rb` (6), `spec/models/attachment_engine_gate_spec.rb` (1), `spec/requests/api/v1/attachments_spec.rb` (1) | **S9** | A chave do catálogo de anexos mudou de `renegotiation.files` para `renegotiation_attachment.file` em `config/attachments.yml`; os specs de S13 ainda afirmam a chave antiga |
| `spec/lib/demo/orchestrator_spec.rb` (11) | **S20** | O orquestrador do seed de demonstração está sendo reescrito à medida que as fatias entregam os models que faltavam |
| `spec/lib/sfg/audit_trail_spec.rb` (2) | **S10/S19** | `IndicatorEntry` inclui `Auditable` sem estar declarado em `VERSIONED` — ver #S4-7 |

**A fatia S4 e todos os specs que ela toca estão verdes:** 194 exemplos / 0 falhas nos 15
arquivos de request e model do escopo (os cinco recursos, o contrato C1, a participação, os cinco
catálogos globais, o portão de readonly e as rotinas de correção de dado). O último `rspec`
**inteiro** verde com a S4 dentro foi **1258 / 0**, momentos antes de as três fatias acima
publicarem — e é a mesma suíte.

**Registrado porque um QA que rode a suíte agora vê 21 falhas** e precisa saber que nenhuma vem
daqui. Uma delas — a de `global_catalog_spec.rb` — **era** da fronteira da S4 e foi corrigida no
mesmo passo: ela afirmava que `RiskControl` **não existia**, o que envelheceu por sucesso quando a
S5 entregou a tabela. O exemplo passou a provar a **propriedade** (nome inexistente é inerte) em
vez do estado de uma fatia num dia.

---

## #S10-1 — o `IndicatorEntry` no `Auditable` deixou o portão da S19 vermelho por ~40 minutos (26/08/2026)

**Não é flag do ai9: é registro de fronteira dentro desta migração**, e a S4 já o viu do outro
lado (#S4-7). O que aconteceu, na ordem:

1. A S10 escreveu `IndicatorEntry` com `include Auditable`, por analogia com `Indicator`.
2. `Sfg::AuditTrail::EXCLUDED` **já declarava** `IndicatorEntry` como fora da trilha, por volume
   de escrita (DEC-78 #1) — a lista da S19 chegou **antes** do model, que é exatamente o desenho.
3. O `include` sem declaração levanta na carga da classe, e
   `spec/lib/sfg/audit_trail_spec.rb` reprova em dois exemplos.

**A trava funcionou como projetada** e o conserto foi remover o `include`, não contornar a
lista. `Indicator` (o cadastro) **entrou** em `VERSIONED` com o motivo escrito, e é uma exceção
deliberada ao "catálogo não entra": renomear um indicador **reescreve `title`/`key`/`value_type`
de todas as suas entries** por `update_all` (T-D11), e como a entry é excluída por volume, sem
essa linha **não existiria lugar nenhum** que registrasse quem reescreveu a série histórica.

**O que fica para quem ler a suíte:** as duas falhas restantes de `audit_trail_spec` às 01:10 de
26/08 são `RiskControl` e `RiskOperation` — declarados em `VERSIONED` e ainda **sem**
`include Auditable` no model. São da **S5/S7**, não da S10.

## #S10-2 — o scratchpad é COMPARTILHADO entre os agentes, e um `shot.mjs` genérico foi sobrescrito no meio da verificação (26/08/2026)

Custou ~20 minutos e produziu duas conclusões erradas antes de ser notado: o navegador headless
morria (outro agente derrubando o processo), a sessão trocava de usuário sozinha (perfil de
navegador compartilhado) e o script de captura passou a imprimir o formato de **outro** agente.

**Regra prática para quem verificar renderizando daqui em diante:** nome de arquivo e **porta de
depuração** próprios da fatia (`s10shot.mjs`, `--remote-debugging-port=9233`,
`--user-data-dir=<scratchpad>/s10/perfil`), e `setsid` no `chrome` para que um `pkill` alheio não
o leve junto.

## #S10-3 — evento sintético de `blur` NÃO exercita o autosave; só o evento de entrada real do CDP exercita (26/08/2026)

Registrado porque a conclusão errada era muito convincente. Dirigindo a célula com
`input.dispatchEvent(new Event('input'))` seguido de `input.blur()`, o campo **exibia o valor
formatado** (prova de que o `onChange` do React rodou) e **nenhuma requisição saía**. A leitura
óbvia — "o autosave está quebrado" — estava errada: `blur()` num elemento que o headless não
focou de verdade não dispara `focusout`, e é `focusout` que o React usa para `onBlur`.

Com `Input.dispatchMouseEvent` (clique real), `Input.insertText` e `Tab` pelo CDP, o handler roda,
o `PUT` sai e a linha aparece no banco com `created_by` da sessão. **Quem for verificar
formulário deste produto: use os eventos de entrada do CDP, não `dispatchEvent`.**

## #S11-1 — `Availability` como nome de classe Grape SOMBREIA o módulo de serviços `::Availability`, e nenhum portão pega (26/08/2026)

O endpoint do painel nasceu como `Api::V1::Availability`. Isso faz com que, **em todo o escopo
léxico `Api::V1::*`**, a constante `Availability` resolva para essa classe: os outros três
endpoints da fatia passaram a procurar `Api::V1::Availability::ProjectTemplateService` e
respondiam **500** em toda requisição.

**O que não pegou:** `ruby -c` (sintaxe válida), `bin/rails zeitwerk:check` (**"All is good!"** —
o autoload está correto; o problema é resolução de constante em tempo de execução) e os specs de
model/serviço (que chamam `Availability::…` do topo, onde não há sombra). Só o **request spec**
mostrou, e ele mostrou como 21 exemplos em 500 de uma vez.

**Duas lições, e a segunda é a que vale para as outras fatias:**
1. classe Grape não deve ter o mesmo nome de um módulo de serviço do domínio — o endpoint virou
   `Api::V1::AvailabilityPanel`, e a rota continua `/api/v1/availability`;
2. **prefixo `::` explícito** nas chamadas de serviço dentro de `Api::V1::*` (`::Availability::…`).
   Custa um caractere e torna a sombra impossível.

Vale conferir se `Api::V1::Risk*`/`Api::V1::Renegotiations` têm a mesma colisão com os módulos
`Risk::`/`Renegotiations::`.

## #S11-2 — o guarda de polling da S0 é TEXTUAL, e reprova comentário que cite a função proibida (26/08/2026)

`src/__tests__/no-api-polling.test.ts` marca como infrator qualquer arquivo que contenha
`setInterval` **e** uma chamada de API. Três arquivos desta fatia foram reprovados por
**comentários** que diziam "não há `setInterval` aqui".

**Não afrouxei o guarda, e a recomendação é não afrouxar:** a severidade está certa — o
comentário de hoje é o `copiar-colar` de amanhã, e um guarda que ignora comentário deixa de ver o
trecho que alguém descomenta. Os comentários passaram a dizer "nenhum temporizador bate na API".
Fica registrado para a próxima fatia não perder tempo descobrindo sozinha.

## #S11-3 — o banco de DESENVOLVIMENTO é compartilhado e o seed de demonstração recria os projetos no meio da verificação (26/08/2026)

Durante a conferência visual o `rake demo:seed` de outra fatia rodou **três vezes**, e a cada vez
os projetos eram recriados com ids novos: o dado de disponibilidade que eu tinha semeado ficava
órfão, o `current_project_id` do usuário de teste mudava sozinho e a tela aparecia vazia — sintoma
idêntico ao de uma consulta com escopo errado.

**Como distinguir em 10 segundos**, antes de investigar a tela: comparar
`User#current_project_id` com o `project_id` do dado que se acabou de semear. Se divergiram, foi
o seed, não o código.

**Recomendação para o orquestrador:** o mesmo isolamento que a DEC-101 já prevê para o banco de
**teste** vale para o de **desenvolvimento** — ou o seed de demonstração ganha um projeto de id
estável, ou cada agente semeia num projeto próprio.

## S9 — renegociações

### F-1 — `AssetsProxyController` serve `public/uploads/**` inline, sem autenticação

**Não mexer.** É da base ai9 e outros sistemas dependem dele (Princípio 6b). Registrado aqui
porque é **literalmente o padrão do D-82** do legado — arquivo estático, URL adivinhável, sem
sessão, `disposition: 'inline'` com o content-type que o uploader declarou.

**O que a S9 fez:** simplesmente **não o usa**. O anexo de renegociação é documento financeiro e
sai por `GET /api/v1/renegotiations/:id/attachments/:id/download`, que autoriza por projeto,
responde `Content-Disposition: attachment` **sempre** e acrescenta `X-Content-Type-Options:
nosniff`. Há um exemplo que confere que **nenhum binário desta fatia existe em `public/`**
(`renegotiation_attachments_spec.rb`).

### F-2 — `api/v1/uploads.rb` grava arquivo de usuário dentro de `public/`

Mesma família do F-1, mesma decisão: a S9 não o usa. Ela consome o motor único da S13
(`Sfg::Attachments` + `config/attachments.yml`), que grava no ActiveStorage privado.

### F-4 — ActiveStorage em `Disk` **também em produção** — requisito de deploy, não de código

`config/storage.yml` usa `service: Disk` em todos os ambientes (DEC-76: Disk na demo, provedor de
produção é item obrigatório do runbook de cutover).

**Consequência concreta para esta fatia:** anexo de renegociação é **documento financeiro**. Disk
em produção exige **volume persistente garantido** — sem ele, o cenário "perda de volume não
derruba a tela" de OPS-192 **não é atingível**, e o efeito visível é o pior possível: a
renegociação lista um anexo e o download falha, o que se lê como "o sistema novo perdeu o
documento". **Bloqueia OPS-192 no deploy**, não no código.

### F-S9-5 — `Grape::Entity` + `Symbol#to_proc` = **500 silencioso**

**Achado ao executar**, custou quatro exemplos vermelhos e um `500` sem stack útil.

`expose :author_id, &:user_id` compila, passa no `zeitwerk:check` e parece idiomático. Mas o
`Grape::Entity` chama o bloco com **dois** argumentos — `(objeto, options)` —, e um
`Symbol#to_proc` repassa o segundo para o método: `a.user_id(options)` levanta
`ArgumentError: wrong number of arguments`. O Grape **engole** a exceção no middleware de
formatação (`caught error of type Grape::Entity::Deprecated in after callback`) e responde
**500 sem dizer por quê**.

**Regra que sai daqui:** em `Grape::Entity`, bloco de `expose` é sempre explícito e de **um**
argumento (`do |a| a.user_id end`). Vale para toda fatia; a base já tem entities com blocos de dois
argumentos, e essas estão certas — o que não pode é `&:símbolo`.

### F-S9-6 — o motor de anexos ficou com o caminho `multiple: true` **sem consumidor**

`Sfg::Attachments` (S13) implementa `has_many_attached` + validador de quantidade + contagem
contra o estado no `attach!`. Depois que a S9 passou o anexo de renegociação para **uma linha por
arquivo** (`renegotiation_attachment.file`, `multiple: false` — a linha precisa de `title`
editável e de `user_id` para a regra de autoria), **nenhuma entrada de `config/attachments.yml`
usa `multiple: true`**.

O caminho não foi removido: ele está correto e a próxima galeria vai querê-lo. Fica registrado
para que ninguém o encontre sem teste e conclua que é código morto — e para que quem o reativar
saiba que precisa **voltar a testá-lo** (o `attachable_multiple_spec.rb` foi retargetado para o
teto por renegociação, que é onde a garantia vive hoje).

## #S11-4 — existem DOIS componentes para os mesmos dois 409 de escopo de projeto (26/08/2026)

`src/components/ProjectScopeState.tsx` e `src/components/ProjectScopeNotice.tsx` resolvem
exatamente o mesmo problema — traduzir `PROJECT_NOT_SELECTED` / `PROJECT_NONE_AVAILABLE` em
estado de tela — com **dois textos diferentes** e a mesma função exportada com o mesmo nome
(`projectScopeCode`) em dois arquivos. Hoje:

- `ProjectScopeState` — risco (S5) e disponibilidades (S11);
- `ProjectScopeNotice` — renegociações (S9) e indicadores (S10).

**Não consolidei**, e o motivo é a Regra de fronteira: são cinco telas de três fatias que estão
sendo escritas **agora**, e trocar o import debaixo delas no meio do trabalho é como se quebra o
que já está de pé. Fica a flag para uma passada única depois que as fatias fecharem.

O sintoma que isso produz se ninguém consolidar é o de sempre nesta migração: **duas frases
diferentes para a mesma situação**, e o usuário concluindo que são situações diferentes. É o
mesmo mecanismo do D-08 (duas somas) e do D-24 (duas semânticas de exclusão), agora em texto de
interface.

## #S13-5 — `after_discard` do ActiveJob dispara em TODA tentativa quando não há `retry_on` (26/08/2026)

Não é defeito da base ai9 nem do legado: é uma semântica do ActiveJob que **parece** dizer outra
coisa. A documentação do `after_discard` fala em *"a job is about to be discarded"*, e a leitura
natural é "quando as retentativas acabarem". Não é o que acontece com o adapter Sidekiq.

Quando o job **não declara `retry_on`**, a retentativa é feita pelo Sidekiq, e ela é **opaca para
o ActiveJob** — que trata toda exceção não tratada como descarte e roda os `after_discard_procs`
**em cada tentativa**.

**Medido** (26/08/2026, Sidekiq no ar, três projetos, um falhando): o
`PropagateGlobalTemplateToProjectJob` registrou `failed` três vezes para o **mesmo** projeto e o
relatório do coordenador fechou `completed: 2, failed: 2` — soma quatro para três projetos.

**Nenhum spec pega isto**, e vale registrar por quê: o adapter de teste desta base é `:inline`
(`config/environments/test.rb:35`), que não retenta. O caminho só existe com o Sidekiq de verdade.

**Onde isto morde nesta base.** Todo job que usa `after_discard` para **contar** ou para
**mudar estado** precisa ser idempotente, ou declarar `retry_on` (o que faz o bloco rodar só na
exaustão). Levantamento em 26/08/2026:

| Job | `retry_on`? | Situação |
| --- | --- | --- |
| `DefaultMemberJob` (S0) | sim, `attempts: 5` | ok — o bloco só roda na exaustão |
| `LinkDefaultMembersJob` (S4) | sim, `attempts: 5` | ok, mesma razão |
| `PropagateGlobalTemplateToProjectJob` (S13) | não | **corrigido**: o desfecho é gravado por projeto, num mapa; os contadores são derivados |

A correção escolhida (registro idempotente por chave) é melhor que declarar `retry_on` porque
não depende da semântica de retentativa de camada nenhuma — e, de brinde, uma retentativa que dá
certo **corrige** o registro anterior em vez de somar por cima.

## #S14-1 — o `CHECK` de `memberships.role` recusa 59% das participações de produção (26/08/2026)

**Dono: S0** (a tabela e o `CHECK` são de `20260825110100_create_memberships.rb`) **com S1**
(a tela de membros). **Não consertei** — mapear os dois valores exige escolher semântica, e
isso é decisão de produto, não de ETL.

O `CHECK` `memberships_role_enum` aceita `responsavel|participante|coordenador|gestor`, que é
o vocabulário declarado pelo model do legado (`membership.rb:18-21`). **O que existe em
produção não é isso:**

| valor | linhas | aceito pelo `CHECK`? |
| ----- | -----: | -------------------- |
| `Participante` | 448 | sim |
| `Responsável` | 17 | sim |
| **`Gerente`** | **655** | **não** |
| **`Colaborador`** | **14** | **não** |

669 de 1.134 (**59%**) foram escritas pelo ETL de 2021
(`../sfg/app/models/legacy/membership.rb:17`), que gravou o **papel GLOBAL** do usuário no
campo de papel do **projeto**, usando a mesma expressão de precedência invertida do Q-16.

**Estado hoje, e é o certo:** `rake sfg_etl:dry_run` **aborta** em
`enums:memberships.role`. O de-para não adivinha, e um papel de projeto errado é rótulo
errado na tela de quem participa do quê.

**O que preciso de vocês:** ou um valor de destino para "Gerente" e "Colaborador", ou a
ampliação do vocabulário. Enquanto não vier, a tarefa fica aberta e a carga de `memberships`
fica bloqueada. Detalhe completo em `legacy-defects.md`, **D-127**.

## #S14-2 — colisão de numeração: existem DOIS `D-124` em `legacy-defects.md` (26/08/2026)

`legacy-defects.md:142` registra `D-124` como "método com nome ofensivo em
`registrations_controller.rb`", e `:239` abre `### D-124 — projects tem DUAS colunas de
cidade`. São defeitos diferentes com o mesmo número.

**Não renumerei**: o `D-124` do nome ofensivo é citado por outras fatias, e trocar número em
uso quebra referência. Fica a flag para quem for consolidar o catálogo — o candidato natural
é dar um número novo ao das duas cidades, que é o mais recente.

Aproveitando: a `analise-dump-producao.md` chama o defeito do `default_position` de
**D-125**, e no catálogo `D-125` é o `ux_kit19` — o número certo é **D-126**, que é o que o
`parity-ledger.md` e o `improvements-log.md` já usam.

## #S1-1 — `PermissionsChannel` assinava o fluxo do `user_id` que o CLIENTE mandasse (26/08/2026)

**Esta é a flag U2, e ela foi CORRIGIDA nesta branch.** Fica registrada porque o defeito
continua na base ai9.

**O que era.** `app/channels/permissions_channel.rb` fazia
`stream_for("permissions:#{params[:user_id]}")` sem conferir nada contra `current_user`.
Qualquer sessão autenticada assinava o fluxo de permissões de qualquer pessoa.

**Por que corrigi aqui em vez de só sinalizar.** A tarefa 8.12 de S1 (`/permissions` com
efeito imediato) precisa exatamente deste canal, e entregar a tela consumindo um canal que
aceita `user_id` alheio seria construir em cima do buraco. Dois canais da própria migração
(`ProjectProgressChannel:10-11`, `RenegotiationChannel:12-14`) já tinham recusado o padrão
**por escrito**, citando esta flag. A mudança é pequena, fechada e testada.

**Como ficou:** o fluxo é sempre o do usuário da conexão. `params[:user_id]` continua sendo
aceito (o front da base o manda) e é **conferido**, não obedecido — pedir o fluxo de outra
pessoa é `reject`, e não um fluxo silenciosamente trocado. Recusar é o que faz um cliente
errado aparecer no log em vez de funcionar por acaso. Emissão por
`PermissionsChannel.publish_changed` / `.publish_user_type_changed`, ponto único, com o
evento carregando **um aviso** e nunca o estado. Specs em
`spec/channels/permissions_channel_spec.rb` (5 exemplos, dois deles sobre a trava).

**Para o ai9:** o `reject` muda o comportamento de qualquer cliente que hoje assine o canal
de outra pessoa — provavelmente nenhum, mas é a razão de ser uma decisão de plataforma.

## #S1-2 — `POST /api/v1/uploads/avatar` da base confiava no `Content-Type` do cliente e não tinha teto (26/08/2026)

**Também corrigida aqui, e também continua na base.** É a flag **F-09** com número.

`api/v1/uploads.rb` fazia `ct.start_with?('image/')` sobre o `Content-Type` que o **cliente**
declarou e gravava o arquivo em `public/uploads/avatars/`, servido como estático sem
autenticação. **Sem teto de tamanho nenhum**: qualquer sessão autenticada enchia o disco da
aplicação, e um `.html` (ou um `.svg` com `<script>`) rotulado como `image/png` era gravado na
árvore pública e servido.

**O Safegold não usa este endpoint** — o avatar do produto sai por
`POST /api/v1/users/:id/avatar`, pelo motor único de anexos (S13/OPS-493). **Mas o endpoint
continua montado**, porque duas telas do assistente interno da base o consomem
(`features/chat-builder/components/AIAgentConfigPanel.tsx:226`, `FlowSettingsModal.tsx:72`).
Removê-lo quebraria as duas (Regra de fronteira) e reescrevê-las é escopo da fatia do chat.

**O que mudou aqui, e só isto:** tipo pelos magic bytes (Marcel, **sem** passar o nome nem o
tipo declarado — medido: um texto puro chamado `fake.png` volta como `image/png` quando o nome
é passado e como `text/plain` quando não é) e teto de 3 MB, o mesmo do catálogo. O contrato de
resposta não mudou; o que passa a falhar é só o que nunca deveria ter passado. Specs em
`spec/requests/api/v1/uploads_spec.rb`.

**O que NÃO foi consertado, e continua flag:** o arquivo ainda vai para `public/uploads/`,
servido sem autenticação. Fechar isso é mover os dois consumidores para o motor de anexos.

## #MOB-1 — Componentes da base ai9 tocados na passada de mobile (DEC-100), 26/08/2026

**Corrigidos aqui, e o achado continua valendo para o ai9.** Todos são mudanças **apenas
abaixo de `md` (768 px)**: acima do breakpoint o desktop renderiza pixel por pixel como antes.

A passada renderizou 33 telas em 390×844 nos dois modos e mediu **31 delas com alvo de toque
abaixo de 44 px**. Nenhuma por descuido de quem escreveu a tela: todas herdavam a mesma altura
de componente da base. A §5.4.8 pede 44 px como critério de aceite, então a correção tinha de
ser no componente — corrigir centenas de call sites com `className="min-h-[3rem]"` é a versão
que a próxima tela esquece.

| Componente | O que mudou | Efeito acima de `md` |
| --- | --- | --- |
| `ui/Button.tsx` | `default`/`sm`/`icon` ganham `min-h-[2.75rem]` no telefone | nenhum (`md:h-10` / `md:h-9`) |
| `ui/Input.tsx`, `ui/SearchInput.tsx`, `ui/DatePicker.tsx` | campo `h-11`, botão de limpar/calendário 44 px | nenhum (`md:h-10` / `md:h-7`) |
| `ui/Select.tsx` | gatilho `h-11`; **opção da lista** com `min-h-[3rem]` | nenhum |
| `ui/tabs.tsx` | `TabsTrigger` com `min-h-[2.75rem]` | nenhum |
| `ui/switch.tsx` | trilho continua 24 px; `::after` invisível estende a **área que responde** para 44 px | `md:after:hidden` |
| `ui/Checkbox.tsx` | idem, e **só quando não há rótulo** (com rótulo o `<label>` já é o alvo) | `md:after:hidden` |
| `components/PageHeader.tsx` | links da trilha com 44 px | nenhum |

**Também na base, e este NÃO é só de mobile:** `ui/States.tsx` não declarava papel ARIA
nenhum. `ErrorState`, `EmptyState` e `LoadingState` eram três `<div>` mudas — a varredura
achou **zero `role="alert"` em 33 telas, nos dois modos**. Para quem usa leitor de tela,
"falhou ao carregar" e "não há nada" eram literalmente a mesma coisa. Agora erro é
`role="alert"` com moldura destrutiva, e carregando/vazio são `role="status"`. O
`AsyncSection` passou a delegar os três estados à biblioteca mobile abaixo de 768 px.

**Para o ai9:** as alturas de 44 px e os papéis ARIA são melhoria pura; o que é decisão de
plataforma é o `AsyncSection` mudar de aparência por largura de janela — um sistema da base
que dependa da moldura exata do `LoadingState` no telefone veria diferença.

## #MOB-2 — `formatarReais` (S4) tem um nome mais estreito que o comportamento

`frontend/src/lib/api/projects.ts`. A função tinha `currency: 'BRL'` literal — a oitava cópia
da decisão que `lib/config/currency.ts` existe para centralizar (§5.4.9). **Corrigido aqui:**
o corpo passou a chamar `formatMoney`, que lê `APP_CURRENCY`.

O **nome** ficou: `formatarReais` formatando em USD quando `VITE_APP_CURRENCY=USD` é
exatamente o tipo de nome que mente e que a Regra de fronteira manda não deixar. Renomear
mexe em ~20 chamadores da S9 (`InstallmentRow`, `RegistrationCard`, `PaymentDrawer`,
`InstallmentsTab`, `InstallmentDrawer`) e é **decisão do dono da fatia**, não da passada de
mobile. Sugestão: `formatarValor`, ou usar `formatMoney` direto e apagar a função.

## #MOB-3 — Restauração de sessão intermitente no console (não é defeito de mobile)

Observado nas três varreduras de 26/08/2026, com o navegador logado por cookie de refresh: em
4 de 66 navegações a tela ficou presa em **"Verificando sessão…"** por mais de 20 segundos, em
rotas diferentes a cada execução (`/faq`, `/risk`, `/providers/:id`, `/dashboard`). Não é
padrão de rota: as mesmas rotas passaram nas outras execuções.

Não mexi — está fora do escopo de mobile e o dono é quem cuida de `ProtectedRoute` /
`RootRedirect` / refresh (S1, que está com `authStore.ts` e `endpoints.ts` abertos agora).
Registrado porque numa apresentação uma tela em branco de 20 s é o pior momento possível.

## #MOB-4 — Campo com `text-sm` faz o Safari do iPhone dar zoom ao focar

`ui/Input.tsx`, `ui/SearchInput.tsx`, `ui/Select.tsx` e derivados usam `text-sm` (14 px). O
Safari do iOS dá **zoom automático** em qualquer campo com fonte abaixo de 16 px ao receber
foco, e depois não desfaz o zoom — a pessoa fica com a página deslocada e tem de pinçar para
voltar. Não aparece no headless nem no DevTools; só no aparelho.

Não corrigi: subir a fonte dos campos para 16 px no telefone é mudança de **tipografia** em
toda a base, não um ajuste de alvo de toque, e merece a decisão de quem cuida do tema (S17).
Fica registrado com a saída conhecida: `text-base md:text-sm` nos campos.

## #F-3 — `rescue_from :all` de `api/v1/base.rb` devolve **backtrace ao cliente** (achado pela S6)

`backend/app/controllers/api/v1/base.rb` tem um `rescue_from :all` que responde 500 com
`e.message` **e o backtrace** no corpo, citando "API ERROR - POLEMK WHATS" — texto de outro
produto. Num endpoint financeiro isso entrega caminho de arquivo, estrutura de diretório e
nomes de classe a quem provocar um 500.

**Não corrigido aqui** (Princípio 6b): o handler é global e mexer nele afeta todos os
endpoints da base, inclusive os de fatias em voo. O que a S6 fez foi o que cabia à fatia —
`rescue_from StandardError` **próprio** em `api/v1/receivables.rb` e `api/v1/charges.rb`, que
loga completo e responde ao cliente uma frase genérica.

**Consequência que quem for consertar precisa saber:** `Grape::Exceptions::ValidationErrors`
é `StandardError`. Um `rescue_from StandardError` local **engole a validação de parâmetro** e
transforma 400 em 500 — o handler local vence o do pai. A S6 tropeçou nisto e a saída foi
declarar `rescue_from Grape::Exceptions::ValidationErrors → 400` **antes** do genérico. Quem
unificar o `rescue_from` global precisa preservar essa ordem.

## #C-7 / #C-8 — correções ao `ai9-base-catalog.md` (transcrição, sem mudança de código)

- **C-7** — `kaminari` e `sidekiq-cron` estão no `Gemfile` e **não** estão catalogados. O
  Kaminari deixou de ser "gem parada" na DEC-62 e hoje é o padrão de paginação de toda lista.
- **C-8** — `image_processing` e o ActiveStorage em `Disk` também não estão catalogados.

## #S6-1 — `Risk::Money` não distingue nulo de zero, e isso é DELIBERADO lá

`app/services/risk/money.rb` faz `value.to_f`, então `nil` vira `0,00`. **Não é defeito na S5**:
aquele módulo existe para replicar byte a byte os `formatted_*` do painel de exposição, que
fazem parte do contrato de paridade (D-95 / DEC-01).

A S6 precisava do oposto (D-117: nulo ≠ zero) e **não** reescreveu a composição: criou
`Sfg::Money`, que **delega** a `Risk::Money.brl` e só acrescenta o `nil` que continua `nil`.
Fica registrado para que ninguém "unifique" os dois achando que são duplicata — eles têm
propósitos opostos, os dois corretos.

## #S6-2 — `ProjectScoped` reporta o erro em `project_id`, e ninguém traduziu isso

`app/models/concerns/project_scoped.rb` faz `validates :project_id, presence: true`.
Sem verbete, a frase do 422 sai **"Project não pode ficar em branco"** — o nome da
classe em inglês no meio de um texto em português, que é o mesmo defeito que a S4
achou em `Company.blocking_dependents`.

A S6 traduziu `project`/`project_id` nos **seus** quatro models
(`receivable_entry`, `charge`, `receipt`, `receivable_tax`). **Não corrigi para os
outros** (regra de fronteira): `Company`, `Provider`, `ProjectGuarantee`,
`RiskControl`, `RiskEntry`, `RiskOperation`, `Renegotiation`, `AvailabilityEntry`,
`IndicatorEntry` e `ProjectIndicatorConnection` incluem o mesmo concern e têm o
mesmo problema.

**A saída boa é uma só**, e cabe a quem cuida do concern: um verbete de nível
raiz em `pt-BR.yml`,

```yaml
pt-BR:
  attributes:
    project_id: "Projeto"
    project: "Projeto"
```

que o Rails usa como fallback quando não há `activerecord.attributes.<model>.<attr>`.
Uma linha resolve para os dez models de uma vez; dez blocos repetidos é o que
produz dez traduções divergentes.

## #S6-3 — **PARA A S20**: o contrato de `ReceivableEntry`, e as duas strings que derrubam o escritor

Entregar os models da S6 virou o escritor `db/seeds/demo/writers/receivable_entries.rb`
de **`:skipped`** para **`:failed`** — antes ele era barrado pelo `requires`
(`MovementKind` não existia) e agora roda. **Não toquei no arquivo** (é da S20, e o
dono está trabalhando nele). Está tudo aqui.

### 1. Os três pontos que quebram, em ordem de quem estoura primeiro

**(a) `MovementKind#movement_kinds` levanta num banco sem catálogo.**
O próprio escritor faz (`:126-129`):

```ruby
raise "Tipos de movimentação ausentes: #{missing.join(', ')} — rode `rake reference:seed`"
```

e `spec/lib/demo/orchestrator_spec.rb` semeia **só** `UserTypes` e `Permissions` no
`before`. **A correção é uma linha no spec**, não no escritor:

```ruby
Seeds::Reference::Runner.call!(io: StringIO.new)
```

O `Runner` é idempotente e pula sozinho o catálogo cuja fatia ainda não entregou o
model — mesmo contrato dos escritores da S20.

**(b) Duas strings do razão não existem no catálogo de produção.**
`db/seeds/demo/ledger/receivables.rb` escolhe catálogo **por título**, e dois títulos
não existem — o `find_by(title:)` devolve `nil` e o model recusa (`presence: true`):

| Linha | Pede | Existe? |
| ----- | ---- | ------- |
| `:109` | `'Cartão de crédito'` | **não** — em produção é **`Cartão`** |
| `:111` | `'Retenção'` | **não existe** como fonte de recurso |

As demais casam. Os títulos disponíveis, medidos no dump de 31/05/2025 e semeados por
`Seeds::Reference::*`:

- **carteiras (12)**: Antecipação · ACE · Desconto · Fomento · ACC · Cheque ·
  Conta Garantida · Comissária · Risco Sacado · Pré-faturamento · Boleto Escrow ·
  Intercompany
- **tipos de recebível (7)**: Duplicata · Cheque · ACC · PAC · **Cartão** ·
  Vale refeição · Intercompany
- **fontes de recurso (6)**: Caixa · Garantia · Comissaria *(sem acento, como em
  produção)* · Fomento · Recompra · 13º salário
- **tipos de movimentação (18)** — as chaves que o escritor usa já existem:
  `desagio`, `advalorem`, `iof`, `outras_despesas`

**Por que o catálogo é este e não o do mapa:** DEC-30. O sistema validado é o que
**rodou**; o mapa dizia 10 carteiras, 5 tipos e 7 fontes, e o dump diz 12, 7 e 6.
A divergência é do mapa.

### 2. O contrato de `ReceivableEntry` — o que é obrigatório

`project` · `company_id` · `carrier_id` · `wallet_id` · `receivable_kind_id` ·
`resource_source_id` · `user_id` (o autor — `BE-182`) · `date` · `qtd_titulos` ·
`valor_bruto` · `prz_med_pond_emp` **> 0** · `prz_med_pond_bco` **> 0** ·
`float_acordado` · `cst_efetivo_acordado`.

**`status` NÃO se preenche à mão** — ele é derivado, sai do
`Receivables::Calculator` junto com os outros 36 e tem `check_constraint`
(`ok` | `difference`). O escritor de vocês já faz certo: `.merge(derived_for(...))`
traz o `status` pronto.

**O portador precisa estar conectado ao projeto** (`ProjectToCarrierConnection`) —
é o mesmo e único critério que o servidor aplica no `create`.

### 3. O caminho mais seguro, se quiserem trocar

Chamar `Receivables::CreateService.call(project:, attrs:, actor:, taxes:)` em vez de
`upsert!(::ReceivableEntry, …)`. É **o mesmo caminho da tela**: os 37 derivados vêm
do único calculador (contrato C2), as tarifas entram na mesma transação e o seed não
pode divergir do produto. O que se perde é o `find_or_initialize_by` do `upsert!` —
daria para manter a idempotência buscando antes e chamando `UpdateService` quando já
existir.

**Não é exigência minha.** O caminho atual (calculador direto + `upsert!`) está
correto e produz os mesmos números; a sugestão é só para que o seed não precise ser
revisto quando a regra de gravação mudar.

---

## S7 — achados na base ai9 (26/08/2026)

### #S7-1 — `aasm` e `pg_search` continuam declaradas e sem um único uso

**Confirmação medida, não achado novo:** a linha 4 da tabela do topo já lista
`aasm`. Esta seção acrescenta a **medição** e um segundo nome.

| Gem | Onde | Ocorrências em `backend/app` |
| --- | ---- | ---: |
| `aasm` | `backend/Gemfile:45` | **0** |
| `pg_search` | `backend/Gemfile:87` | **0** |

**Por que a S7 mediu isto.** Esta fatia tem os dois candidatos naturais:

- **`aasm`** — `risk_operations.is_ended` e `is_on_variable` são estado. A
  tentação é modelá-los com máquina de estados. **Não foi feito**, e não é
  esquecimento: por **DEC-35** o `is_ended` é **rótulo** — não bloqueia
  movimento, não bloqueia prorrogação e não retira a operação da exposição.
  Uma máquina de estados sem transição proibida é cerimônia; e ativar uma gem
  compartilhada para isso é decisão de plataforma, não de fatia. Ficaram
  `boolean` + serviço, que é o padrão vivo da base (`ai9-conventions.md` §9.6).
- **`pg_search`** — a busca da lista de operações é `carriers.title ILIKE ? OR
  risk_operations.title ILIKE ?` (`risk_operations_controller.rb:30`). `ILIKE`
  nativo com bind e `sanitize_sql_like` é o que a S5 e a S6 já usam; trocar por
  `pg_search` aqui criaria **dois** dialetos de busca no mesmo bloco.

**Nada a fazer nesta migração.** As duas ficam registradas para o ai9: gem
declarada e sem uso é peso no `Gemfile.lock` e sugestão falsa de recurso
disponível. Remover é decisão de plataforma — afeta todos os sistemas da base.

### #S7-2 — `Campo` (de `CatalogFields`) tipava `label` como `string`

**Corrigido nesta fatia**, e a correção é de uma linha:
`app/pages/catalogs/CatalogFields.tsx` declarava `label: string`, mas o rótulo
precisa carregar o `<FieldHelp>` ao lado do texto (OPS-545 / DEC-88) — que é
`ReactNode`. O primeiro formulário que precisou do ícone recorreu a
`as unknown as string`, cast que **compila e mente**.

A assinatura passou a `label: ReactNode`. **Alarga**, não quebra: toda chamada
existente com `string` continua válida. Registrado aqui porque é componente
compartilhado, tocado por uma fatia de risco.

### #S7-3 — o seed de demonstração e o motor da S7 concordam (medido duas vezes, com resultados opostos)

**Não é flag de base ai9; é um cruzamento entre fatias, e fica registrado porque é a
coisa mais próxima de um segundo oráculo que esta fatia conseguiu.**

A S7 não tem oráculo de produção (as seis migrações da família nunca subiram). O que
existe é uma **segunda implementação independente** da mesma cadeia: o seed de demo da
**S20**, que escreve `risk_movements.balance` por conta própria.

Medição, com script somente-leitura contra `sfg9_dev`, percorrendo **todas** as operações
não estáticas com movimento e recalculando a cadeia pela regra da S7
(`prev + credit_type_value × movement_value`, começando em `original_balance`):

| Quando | Operações com movimento | Divergentes |
| --- | ---: | ---: |
| 26/08/2026 ~12:33 | 855 | **855** |
| 26/08/2026 ~13:05, depois de o seed ser reexecutado (`max(created_at) = 12:56`) | 855 | **0** |

Na primeira medição o seed usava a convenção **oposta** (`D → −1`, `C → +1`) e começava a
cadeia em **zero** em vez de `original_balance`; na segunda, as 855 cadeias reproduzem o
motor **linha a linha**. A reexecução do seed foi feita por outro agente, em paralelo, e
não por esta fatia — o que se registra aqui é a **medição**, não a causa.

**Por que isto vale registro:** duas implementações escritas separadamente, a partir da
mesma fonte de 2022 (`../sfg/app/models/risk_operation.rb:98-111` e
`risk_movement_type.rb:53-61`), chegando ao mesmo número em 855 cadeias, é evidência —
**não é oráculo**. Ela não prova que o número está certo; prova que duas leituras
independentes do mesmo código de 2022 coincidem. A distinção continua valendo, e a
tarefa 11.4 da S7 continua aberta por isso.

**Consequência prática que vale para quem for editar dado de demo:** salvar qualquer
operação (pela tela ou por `rails runner`) **reescreve a cadeia inteira** dela, porque o
recálculo roda no `before_validation` de todo save. Enquanto as duas convenções
coincidirem, nada muda; se o seed divergir de novo, a primeira edição de uma operação
semeada vai mudar os saldos dela na tela — e isso pareceria bug sem esta nota.

---

## S8 — achados na base ai9 (26/08/2026)

### #S8-1 — `pg_search` e `paper_trail`: a S8 confere, e o quadro mudou de metade

Tarefa 0.7. Os dois nomes **já estão registrados** — na linha 4 da tabela do
topo e na seção `#S7-1`. Esta entrada é a **conferência da S8**, não uma
duplicata, e ela corrige metade do registro:

| Gem | Estado medido pela S8 | Veredito |
| --- | --------------------- | -------- |
| `pg_search` (`backend/Gemfile:87`) | **0** usos em `backend/app` | continua sem uso, e **de propósito** nesta fatia |
| `paper_trail` | **em uso**, e a S8 acrescentou uma linha | o risco descrito no `design.md` §6 **não existe mais** |

**`pg_search`.** A busca desta unidade é
`carriers.title ILIKE :q OR structured_operations.title ILIKE :q`, com o termo
escapado por `sanitize_sql_like` e passado por bind — o mesmo dialeto de S3, S5,
S6 e S7. Trocar por `pg_search` só aqui criaria o segundo dialeto de busca da
base. Fica como opção de plataforma.

**`paper_trail` NÃO está mais "no Gemfile sem uso".** O `design.md` §6 da S8 foi
escrito quando isso era verdade e diz, na tabela de "registrar, não corrigir":
*"`paper_trail` no Gemfile **sem uso**; a auditoria da base é ad hoc →
`created_by_id`/`updated_by_id` com FK real, **sem ativar a gem**"*. Entre o
desenho e a execução, a **DEC-59** e a **DEC-78** entraram e a S19 montou
`Sfg::AuditTrail`, com lista deliberada e portão que levanta para model não
declarado.

Então a S8 fez as **duas** coisas, que não são alternativas:

- `structured_operations.user_id` (autor) e `updated_by_id` (último editor) com
  **FK real**, preenchidos no servidor — que é o `DB-297`;
- `StructuredOperation` e `Remuneration` **versionados**, com a linha declarada
  e o motivo escrito. `StructuredOperationType` e `ResourceSource` foram para
  `EXCLUDED`, também com motivo.

**Registrado porque a instrução do `design.md` §6, lida hoje ao pé da letra,
manda não ativar a gem — e seguir isso agora seria deixar a operação
estruturada fora da trilha financeira que a `RiskOperation`, o `Receipt` e a
`Charge` já têm.** A instrução envelheceu; o motivo dela não se aplica mais.

### #S8-2 — `Charges::BulkReceiptsService` destruía o recibo antes de soltar a operação

**Corrigido nesta fatia**, e é o achado mais sério da rodada — ver
`improvements-log.md`, `EST-S8-01`.

`remove_unlisted!` fazia `receipt.destroy!` e **só depois**
`operacao.update!(receipt_id: nil)`. Com as FKs reais de
`risk_operations.receipt_id` (S6) e `structured_operations.receipt_id` (S8), o
Postgres recusa a exclusão do recibo enquanto a operação ainda aponta para ele:

```
PG::ForeignKeyViolation: update or delete on table "receipts" violates
foreign key constraint on table "structured_operations"
```

**O lado LIQ estava quebrado desde a S6** e ninguém podia saber: sem o model
`Remuneration`, `BulkReceiptsService` parava no 422 que nomeava a fatia S8, e o
caminho de remoção **nunca era alcançado por teste nenhum**. A S8 é a primeira
fatia capaz de executá-lo, e o primeiro "desmarcar" deu 500.

A ordem foi invertida (solta a operação, depois destrói o recibo), na mesma
transação, com o motivo escrito no método — porque a ordem parece arbitrária e
não é. **Fica registrado para a S6**: o defeito era do arquivo dela, a correção
está no arquivo dela, e o spec que o trava está em
`spec/requests/api/v1/structured_operations_spec.rb` ("o vínculo com o recibo,
ida e volta").

### #S8-3 — o banco de teste `sfg9_test` é COMPARTILHADO entre os agentes, e isso produz falha falsa

**Não é defeito de código. É bancada, e vale para quem for ler o portão.**

Em 26/08/2026 há 4–5 fatias em voo na mesma árvore, e todas rodam `rspec`
contra o **mesmo** `sfg9_test`. Duas consequências medidas:

1. **`PG::ObjectInUse` no `db:test:purge`** — `bin/rails aborted! database
   "sfg9_test" is being accessed by other users. DETAIL: There are 3 other
   sessions using the database.` O `maintain_test_schema!` falha, a suíte roda
   assim mesmo, e o erro aparece no topo da saída como se fosse do código.
2. **`PG::TRDeadlockDetected` em `index_user_types_on_hierarchy_level`** —
   dois processos de `rspec` inserindo `user_types` ao mesmo tempo travam um
   ao outro. A falha aparece em `spec/factories/users.rb:29`
   (`user_type { UserType.og || create(:user_type, :og) }`), ou seja, **em
   qualquer spec que crie um usuário** — o que significa qualquer spec.

Evidência de que é contenção e não regressão, medida na mesma máquina em
minutos consecutivos:

| Execução | Resultado |
| -------- | --------- |
| `spec/services/structured` + os 2 model specs, isolados | **52 exemplos, 0 falhas** |
| Os 3 request specs da S8, isolados | **78 exemplos, 0 falhas** |
| `charges_spec.rb` isolado, antes de as outras fatias subirem | **50 exemplos, 0 falhas** |
| Os mesmos arquivos + `charges_spec` com 3–5 agentes rodando junto | 197 exemplos, **7 falhas**, todas `TRDeadlockDetected` |
| `charges_spec.rb:615/621/633` sozinhos, com outro agente rodando | 3 falhas, todas `TRDeadlockDetected` no mesmo índice |

**A prova mais forte, e ela chegou depois:** durante uma das execuções, outro
agente **APAGOU o banco no meio da corrida** —

```
FATAL:  database "sfg9_test" does not exist
DETAIL:  It seems to have just been dropped or renamed.
```

— que é o `db:test:purge` de um processo concorrente derrubando a suíte alheia.
Não há como uma suíte sobreviver a isso, e não há como o resultado dela ser
lido como estado do código.

**A reprodução que fecha o assunto.** A primeira execução da suíte inteira
listou **40 exemplos falhos** em 6 arquivos: 38 em `spec/services/risk/*`
(renovação/prorrogação, transferência, par estático, contrato de borderô), 1 em
`spec/services/users_service_spec.rb` e 1 em
`spec/services/structured/remuneration_calculator_spec.rb:147` (o `temp_id` do
lado **LIQ**). Rodando **os mesmos dois diretórios juntos, no mesmo processo e
na mesma ordem**, com a máquina mais calma:

```
bundle exec rspec spec/services/risk spec/services/structured
131 examples, 0 failures
```

Não é "passou isolado": é a **combinação exata** que falhou 39 das 40 vezes,
verde de ponta a ponta. O que muda entre as duas execuções não é uma linha de
código — é quantos agentes estão escrevendo no mesmo `sfg9_test`.

**Para o QA do Phase 4:** rodar a suíte com a máquina só para ela, ou dar a
cada fatia o seu `TEST_ENV_NUMBER`/banco. Uma falha em
`index_user_types_on_hierarchy_level` vinda de `spec/factories/users.rb:29`
deve ser relida como contenção antes de ser lida como regressão.

**Também em voo, e não é meu:** `db/migrate/20260826235000_indicators_scope_explicito.rb`
(S10) e `db/migrate/20260826235100_carimbo_de_gestao_nas_tabelas_filhas.rb`
estavam **pendentes** no banco quando terminei, o que faz
`ActiveRecord::Migration.maintain_test_schema!` recusar a suíte inteira com
`PendingMigrationError`. Não as rodei: são de outras fatias, e migrar por cima
de trabalho alheio é como o `schema.rb` volta a reintroduzir feature removida.

---

## S8/frontend — `DataTable`/`Table`: a largura de coluna é só sugestão (26/08/2026)

> **RESOLVIDO em 26/08/2026, com aval do usuário.** `DataTable` ganhou
> `layout?: 'auto' | 'fixed'`, **default `auto`** — nenhuma tela existente muda de
> comportamento, e `Table` não foi tocado (ele já repassava `className`). Quem declara
> `width` passa a `layout="fixed"` e recebe o que declarou. O registro abaixo fica como
> está, porque é ele que explica **por que** a mudança valeu a exceção ao princípio 6b:
> o mesmo remendo manual já existia em duas telas.
>
> **FECHADO POR COMPLETO em 26/08/2026 (segunda passada, achado do usuário).** A
> `layout='fixed'` resolvia a largura **declarada**; ela não resolvia o que sobra **fora da
> área visível**. Em `/renegotiations` a 1440×900 a última coluna visível vinha cortada no
> meio de um valor (`R$ 2…`), as seguintes não existiam para quem olha, e nenhum sinal
> dizia que dava para rolar — `Table` é `overflow-auto`, mas `globals.css` apaga a barra de
> rolagem de todo container do app, e rolagem invisível é o mesmo que rolagem inexistente.
>
> O que entrou, tudo **aditivo** e no compartilhado: `Table` aceita `wrapperProps` /
> `wrapperRef` (sem eles o markup é byte a byte o de antes); `DataTable` ganhou barra de
> rolagem visível (`.table-scroll-x`), **cortina opaca** do tamanho exato do pedaço de
> coluna que sobrou, encaixe de rolagem com recuo (`.table-snap-x` + `scroll-padding-left`),
> primeira coluna congelada só quando há transbordo, e `mobile='cards'` no telefone. Dois
> tokens de elevação novos (`--elevation-sticky-col`, `--elevation-scroll-edge`), claro e
> escuro. **Nenhuma das 18 telas precisou mudar.** Detalhe em `improvements-log.md`
> **DS-01** / **DS-02**; o descuido de percentual da mesma captura está em **DS-03**.

`components/ui/DataTable.tsx` aceita `width` por coluna e repassa como `style={{ width }}`
no `<th>`, mas `components/ui/Table.tsx` renderiza `<table className="w-full …">` **sem**
`table-layout: fixed`. Em `table-layout: auto` a largura declarada vira um mínimo negociável e
quem manda é o conteúdo — então uma coluna com texto longo (um nome de portador, um título de
operação) **empurra a tabela para fora do container** e as últimas colunas somem à direita.
`overflow-x-auto` no wrapper salva do estouro do layout, mas o efeito prático é a coluna de
**ações** ficar invisível sem rolagem lateral.

Aconteceu na lista de operações estruturadas (`FE-280`) com dez colunas. Contornado **na tela**,
sem tocar na base: o limite passou a ser `max-w` no **conteúdo** da célula, que é o que faz a
truncagem valer com `table-layout: auto`. O mesmo contorno já aparece, escrito à mão, na lista de
operações de risco da S7 — duas telas com o mesmo remendo é o sinal de que o lugar certo é a base.

**Candidato upstream:** `DataTable` expor `layout?: 'auto' | 'fixed'` (default `auto`, para não
mudar nenhuma tela existente) e repassar `table-fixed` ao `Table`. Quem declara `width` nas
colunas passa a receber exatamente o que declarou, e `truncate` funciona sem `max-w` por célula.
**Não é bloqueante para esta app.**

## S8/frontend — botão primário `disabled` não se lê como desabilitado no modo escuro (26/08/2026)

**Não corrigido de propósito.** Mesmo motivo.

`components/ui/Button.tsx` usa `disabled:opacity-50`. Sobre o fundo claro isso dá um amarelo
lavado que lê como inativo na hora; sobre o fundo escuro, 50% do amarelo da marca ainda é um
bloco brilhante — visualmente **indistinguível** do botão ativo. Capturado lado a lado no
formulário de operação estruturada: o mesmo estado (três campos obrigatórios vazios, a barra
dizendo o que falta) parece bloqueado em claro e liberado em escuro.

Nesta tela o dano é limitado, porque a barra **escreve** o motivo e o `Tooltip` repete no hover —
o usuário não fica sem explicação. Mas é um comportamento da base que atinge todo botão primário
desabilitado do app nos dois modos.

**Candidato upstream:** no modo escuro, `disabled` não deveria ser só opacidade — trocar por
superfície `muted` com `on-muted`, ou baixar a opacidade bem mais, medindo contraste nos dois
modos. Dono: **theming-brand-engineer** (é token/componente compartilhado, não tela).

---

## UF-S4-06 — `SideDrawer` não expõe `role="dialog"` (base ai9, S0)

`frontend/src/components/SideDrawer.tsx` é o painel lateral que **toda** tela de cadastro
desta migração usa. Ele é uma pilha de `<div>` com `data-helper` no backdrop e **nenhum papel
ARIA**: não há `role="dialog"`, `aria-modal`, nem `aria-labelledby` apontando para o título
que ele já renderiza.

**Como apareceu:** verificando a tela "Indicadores específicos" renderizando, `page.locator('[role="dialog"]')`
devolveu **0** com o painel aberto na frente. O painel funcionava — abriu, tinha os campos, e
salvar criou a linha —, mas nenhum leitor de tela o anuncia como diálogo, e nenhum teste de
acessibilidade o encontra pelo papel.

**Não corrigido aqui de propósito:** é componente **compartilhado** da base, usado por outras
fatias e por outros sistemas que rodam sobre o ai9. Acrescentar `role="dialog"` +
`aria-modal="true"` + `aria-labelledby` é pequeno e provavelmente seguro, mas muda o
comportamento de foco/leitor em **todas** as telas de uma vez.

**Dono:** S0 / design-system. **Alcance:** toda tela com painel lateral.

---

## UF-S4-07 — Data inválida responde **400**, e a tarefa da S4 pedia 422

A tarefa 5.1.9 (`BE-052`) pedia *"data inválida → 422 e não 500"*. Verificado executando,
`GET /api/v1/companies/risk_summary/list?date=lixo` responde **400** com
`{"error":"date é inválido"}` — **não é 500**, que era o ponto, mas também não é 422.

O 400 vem de `rescue_from Grape::Exceptions::ValidationErrors` em
`api/v1/base.rb:253`, e `optional :date, type: Date` é o padrão de **toda a base** (26
ocorrências em 8 controllers: `charges`, `receivables`, `projects`, `providers`, …). Trocar o
`rescue_from` para 422 mudaria o código de erro de coerção de **todos** os endpoints do
produto de uma vez; validar a data à mão só neste endpoint criaria um segundo padrão e perderia
a validação declarativa que a própria tarefa pede.

**Decisão desta fatia:** ficar com o 400 e registrar. O contrato observável que importava
(nunca 500) está cumprido e travado por verificação.

**Dono:** orquestração — vale uma decisão explícita se 400 ou 422 é o código de coerção do
produto. **Alcance:** todo endpoint com parâmetro tipado.

---

## UF-S4-08 — `Risk::AggregateService.total_limits_on` mistura tipos e formata dentro do domínio

A tarefa 5.1.9 pedia *"agregados como número, formatação fora do backend"*. O que o endpoint
devolve hoje (medido, `GET /companies/risk_summary/list?date=2025-05-31`):

- `total` e `util` → **string** decimal (`"1217685.69"`) — `BigDecimal` serializado;
- `disp` → **Float** (`1220029.68`), porque `limite_disponivel_on` termina em `.to_f`;
- `perc_util`, `liq`, `perc_liq`, `pre`, `perc_pre` → **string formatada** (`"-0.19%"`);
- `formatted_total` / `formatted_disp` / `formatted_util` → formatação pt-BR **no servidor**.

O `.to_f` do `disp` e as quatro chaves de percentual iguais são **réplica deliberada** do
legado (`../sfg/app/models/company.rb:68-88`), travadas por golden da S5 — mexer nelas muda
exposição financeira e é exatamente o que a regra 4 proíbe. Os `formatted_*` são acréscimo da
S5, **aditivos**: os números crus continuam lá, e é deles que a S4 depende.

**O que fica como candidato:** unificar o tipo de `total`/`disp`/`util` (os três como decimal
em string, ou os três como número) sem mudar o **valor**, e mover os `formatted_*` para o
cliente. Precisa de decisão porque o payload já tem consumidor.

**Dono:** S5 / bloco `risk`. **Alcance:** `risk_summary` da empresa e a tela de risco.

---

## UF-S15-01 — `RechartsLine` e `RechartsBar` não têm gancho de formatação, e o eixo Y tem largura fixa

**Onde:** `frontend/src/components/charts/RechartsLine.tsx`, `RechartsBar.tsx` (base ai9).
**Visto renderizando**, não deduzido: `/dashboard`, seed de demonstração, 1440×900.

Dois defeitos, os dois na frente do cliente:

1. **Tooltip com o número CRU.** `RechartsLine` imprime `{val}` direto
   (`RechartsLine.tsx`, corpo do `Tooltip`), então um total de borderô aparece como
   `605602.54` — ponto decimal de JavaScript, sem separador de milhar e sem `R$`.
   `RechartsBar` faz o oposto e igualmente errado: crava `R$ ` no prefixo, então uma
   série que **não** é dinheiro sai com símbolo de moeda.
2. **Rótulo do eixo Y cortado.** A largura do `YAxis` é a padrão do Recharts (60 px) e o
   componente não a calcula a partir do dado. Com sete dígitos o eixo mostrava `00000`
   e `0` — o começo do número comido pela borda da área de plotagem. É a mesma classe do
   achado da S8 (largura declarada tratada como sugestão).

Nenhum dos dois tem prop que permita corrigir de fora: `{ labels, values }` é a assinatura
inteira.

**O que a S15 fez, e o que NÃO fez.** Não editou nenhum dos dois arquivos (Princípio 6b,
tarefa 3.4 da fatia) — e a varredura `indicatorCharts`/`dashboard.test` trava a assinatura
dos dois para avisar se alguém editar. Em vez disso nasceram três **membros novos** da
biblioteca, que é onde o app passa a construir gráfico daqui em diante:
`components/charts/SeriesLineChart.tsx`, `CategoryBarChart.tsx` e `LimitMeters.tsx`, com
`chartFormat.ts` decidindo formato num lugar só.

**Candidato para o ai9 (patch pequeno e seguro):** dar aos dois componentes uma prop
opcional `formatValue?: (n: number) => string` e uma `yAxisWidth?: number`, com o
comportamento atual como padrão. **Medido:** `RechartsLine` e `RechartsBar` não têm
**nenhum** consumidor na base — nem tela nem galeria (`UiKitPage` importa só o
`RechartsPie`) —, o que torna a mudança de risco praticamente zero e é a razão de ela
valer a pena. `RechartsPie` é o único dos três com consumidor, e ele não é tocado por
esta proposta.

**Dono:** time do ai9 base / design system. **Alcance:** qualquer tela futura que use os
dois componentes.

---

## UF-S15-02 — a paleta categórica de `charts/theme.ts` reprova no validador, nos DOIS modos

**Onde:** `frontend/src/components/charts/theme.ts`, constante `SERIES` (consumida por
`defaultPalette()`, `vibrantPalette()` e `RechartsPie`).

Medido com o validador do skill `dataviz`
(`scripts/validate_palette.js`), superfícies `#ffffff` (claro) e `#20201d` (escuro):

| verificação | claro | escuro |
| ----------- | ----- | ------ |
| faixa de luminosidade | **FALHA** (`#ffc105` 0,844; `#7b1f1e` 0,39) | **FALHA** (`#ffc105`; `#8ba5b1`) |
| piso de croma | **FALHA** (`#607c8a` lê como cinza) | **FALHA** (`#8ba5b1`) |
| separação sob daltonismo | AVISO — ΔE 7,1 (deutan) entre aço e verde | passa |
| piso de visão normal | **FALHA** — ΔE 10,6 (mínimo 15) | **FALHA** — ΔE 13,8 |
| contraste com a superfície | AVISO — `#ffc105` a **1,63:1** | passa |

O achado que mais importa para a marca: **o ouro Safegold (`--primary`, `#ffc105`) não
alcança 3:1 sobre o card claro** e, por isso, **não pode carregar dado** no modo claro —
nem como preenchimento de barra, nem como linha. `--brand-gold-deep` (`#eb9500`) também
não chega lá (2,38:1). Isso não é defeito da marca: ouro é cor de ação, e continua sendo a
cor do botão primário. É defeito de **usar a cor de ação como cor de série**.

**O que a S15 fez:** não tocou em `theme.ts`. Registrou os tokens de dado em
`components/charts/chartTokens.ts` (`--info` para a medida; `--success`/`--negative` só
quando a cor SIGNIFICA estado, sempre com ícone e rótulo junto) e usa apenas séries de uma
cor, onde a verificação categórica não se aplica.

**Candidato para o ai9:** re-degrau da constante `SERIES` contra o validador, nos dois
modos, tirando o ouro e o aço da paleta de dado. **Alcance:** `RechartsPie` e qualquer
gráfico multi-série futuro.

**Dono:** design system / `theming-brand-engineer`.

---

## UF-S15-03 — `KpiCard` não encolhe nem trunca valor longo, e o número é CORTADO

**Onde:** `frontend/src/components/kpi/KpiCard.tsx`, o `div` do valor
(`text-4xl font-numeric`).

**Visto renderizando:** com quatro cartões numa linha em 1440×900 o card tem ~316 px
úteis; `R$ 9.286.435,25` em `text-4xl` (36 px) na Fira Mono precisa de ~372 px. O último
dígito ficava **fora da borda** — `R$ 9.286.435,2`. Num sistema de crédito isso não é
detalhe de layout: é um número errado na tela, e nenhum type-check o pega.

**O que a S15 fez:** não editou o componente. O painel passou a duas colunas e o
consumidor rebaixa o valor para `text-3xl` por seletor de descendente
(`[&_.text-4xl]:text-3xl` no elo que envolve o cartão) — especificidade maior, sem
`!important`, sem tocar no compartilhado.

**Candidato para o ai9:** o `KpiCard` decidir o corpo do valor a partir do comprimento do
texto (ou usar `clamp()`), já que ele é quem sabe a largura do próprio card.
**Alcance:** todo painel que mostrar moeda com sete dígitos ou mais.

**Dono:** design system.

---

## UF-S15-04 — `src/test/setup.ts` não registra o `cleanup()` do testing-library

**Onde:** `frontend/src/test/setup.ts`.

O arquivo importa `@testing-library/jest-dom` e configura `clipboard`/`location`, mas
**não** chama `cleanup()` num `afterEach`. Consequência medida: a tela de um exemplo
continua montada durante o exemplo seguinte, com a consulta dela viva. O sintoma não
aponta para a causa — a rejeição do exemplo seguinte aparece como **rejeição sem dono**, e
o teste que prova o tratamento do erro reprova por causa disso. Levou uma bateria de
tentativas para achar, porque `-t` de um exemplo só reproduz o problema (o `beforeEach`
continua rodando).

**O que a S15 fez:** chamada explícita de `cleanup()` no `beforeEach` dos dois arquivos de
teste da fatia.

**Candidato para o ai9:** `afterEach(cleanup)` no setup compartilhado. **Alcance:** toda a
suíte de front — hoje cada arquivo herda o mesmo modo de falha.

**Dono:** plataforma / base ai9.

---

## UF-S2-01 — o `rescue_from :all` do Grape engole o 405 e devolve 500 com o backtrace

**Onde:** `backend/app/controllers/api/v1/base.rb` (o handler herdado da base ai9 — o rótulo
`API ERROR - POLEMK WHATS` no meio dele denuncia a origem) e `app/controllers/api/root.rb:239-242`,
que tem cópia do mesmo trecho.

**Medido, não deduzido.** Servidor de dev, sessão de Admin de verdade:

```
GET /api/v1/project_carrier_connections/<uuid>   →  HTTP 500
allow: OPTIONS, DELETE
{"error":"ERROR - API POLEMK: 405 Not Allowed <br/> \n BACKTRACE: /home/…/grape-3.1.1/…"}
Content-Length: 9549
```

**Duas coisas erradas na mesma resposta:**

1. **405 vira 500.** O Grape levanta `Grape::Exceptions::MethodNotAllowed`, que já carrega o
   status certo (e o cabeçalho `Allow` sai correto ao lado). O `unless` do handler só decidia
   se montava uma variável local `env` **que nunca é usada**; o `error!(error_backtrace)` no
   fim rodava para toda exceção, sem status — e `error!` sem status é 500. O mesmo vale para
   `InvalidVersionHeader` e o resto da família `Grape::Exceptions::Base`.
2. **O backtrace inteiro vai no corpo, em qualquer ambiente.** 9,5 KB de caminhos de gem,
   versões e o caminho absoluto do código no disco, para qualquer cliente da API. É o flag #3
   da tabela acima, agora com número.

**O que a S2 fez (tarefa 2.8):** `rescue_from Grape::Exceptions::Base` devolvendo `e.status`, e
o `rescue_from :all` passando a logar o backtrace e a responder um corpo genérico com o
`X-Request-Id` para casar log e resposta. Pinado em
`spec/requests/api/v1/detail_routes_spec.rb`. Alterado na base por **DEC-50** (a `sfg9` é
produto próprio) e porque a tarefa 2.8 exige que rota de detalhe nunca responda 500.

**Alcance no ai9:** toda API montada nesse root — qualquer verbo errado em qualquer rota, em
todos os derivados.

**Dono:** plataforma / base ai9.

---

## UF-DS-01 — número cru em tela do chat-builder da base ai9 (26/08/2026)

**Achado na varredura de "ponto decimal em tela portuguesa"** pedida junto com o DS-03.
Fora do escopo desta migração, e por isso **não corrigido** (Princípio 6b): são telas da
**base ai9**, do chat-builder, alimentadas por `mockAnalytics`.

| Onde | O que sai |
| ---- | --------- |
| `frontend/src/features/chat-builder/FlowListPage.tsx:556` | `totalConversations.toLocaleString()` — **sem locale**: usa o do navegador, então a mesma tela escreve `1,234` num aparelho e `1.234` noutro |
| `FlowListPage.tsx:564,572,616` | `` `${mockAnalytics.avgFlowCompletion}%` `` e `{completion}%` — número cru; hoje são inteiros, e é só isso que esconde o defeito |
| `MobileFlowListPage.tsx:598` | `{item.value}%`, idem |

**Por que importa mesmo sendo mock:** o dado vira real um dia, e o formato não muda junto —
foi exatamente assim que `66.87% Pago` chegou à tela de renegociações. O caminho já existe na
base: `lib/utils/number` (`formatAmount`, `formatPercent`) com o locale de
`lib/config/currency`.

**Também registrado, e este é de decisão, não de descuido:**
`frontend/src/features/dashboard/components/NearCeilingPanel.tsx:77,81` interpola
`${dados.threshold}%` cru. O servidor manda `80`, então hoje sai certo; um limiar fracionário
(`82.5`) sairia com ponto. Deixado como está para não mudar texto de painel sem necessidade —
mas é a mesma classe.

**No backend:** `Risk::Money.percent` (`backend/app/services/risk/money.rb`) formata com
`sprintf('%.2f', …) + '%'` — **ponto decimal**, réplica declarada do legado
(`../sfg/app/models/company.rb:41`). Ele alimenta `perc_util`/`perc_liq`/`perc_pre` de
`total_limits_on` e o `percent_label` do painel. O painel já passa por
`localizePercentLabel` (S15); `total_limits_on` **não tem consumidor no frontend hoje** —
quando tiver, tem de passar pelo mesmo helper, e não pelo `formatPercent` (arredondar de novo
um valor já arredondado cria uma segunda decisão sobre o mesmo número, que é o D-09).

**Dono:** time do ai9 base (chat-builder) / orquestração (o limiar do painel).

## UF-DS-02 — `useMobile` decide por `window.innerWidth`, e o `DataTable` agora depende disso

Com o `mobile='cards'` do DS-02, o `DataTable` passou a consumir `hooks/useMobile`, que lê
`window.innerWidth < 768` na inicialização e escuta `resize`. Duas consequências que valem
registro, **nenhuma bloqueante**:

1. Não há `matchMedia`, então em ambiente sem `window` dimensionado (jsdom padrão: 1024) o
   resultado é sempre "desktop". Isso é o que mantém as 51 suítes do front verdes sem
   nenhuma mudança — é conveniente aqui e é sorte, não desenho.
2. Cada `DataTable` na tela registra o seu próprio ouvinte de `resize`. Com uma listagem por
   página isso é um ouvinte; numa tela com abas e três tabelas montadas, três.

**Candidato para a base:** `useMobile` sobre `matchMedia('(max-width: 767px)')` com uma
assinatura compartilhada. **Dono:** plataforma / base ai9.


## UF-WA-01 — `Api::Root` listava o endpoint que REGISTRA webhook como rota pública

**Arquivo:** `backend/app/controllers/api/root.rb`, allowlist `public_paths`.
**Entrada removida:** `%r{^/whats/v1/webhooks/config/?$}`.

A allowlist de `public_paths` existe para os **receptores** de webhook: quem os chama é a
Evolution, que não tem sessão nossa para apresentar. `connection-update`, `qrcode-updated` e
`logout-instance` são isso e continuam na lista.

`config` **não** é receptor — é o painel que diz à Evolution para onde mandar evento. Estando
na lista, o efeito não foi "ficou aberto": foi o **oposto, e mudo**. O `before` do `Api::Root`
fazia `next` e nunca preenchia `@current_user`; o endpoint então conferia `@current_user&.og?`
(`api/whats/v1/webhooks.rb:79`), achava `nil`, e respondia **401 a todo mundo — OG inclusive**.
Medido em 26/08/2026 com token OG válido contra o servidor de pé: `HTTP=401`.

**Consequência de produto:** registrar o webhook pelo app era impossível. A instância
`AI9_VINAO` ficou com o placeholder `https://tst` e, do lado da Evolution, `enabled: false` e
`events: []` — sem `CONNECTION_UPDATE` nem `QRCODE_UPDATED`. O celular pareava, nenhum evento
chegava, nada era transmitido pelo Action Cable, e a tela de pareamento ficava parada sem erro
nenhum. Foi o defeito relatado pelo usuário.

**Por que está aqui e não só no commit:** `api/root.rb` é o gate central de autenticação da
base ai9 e é código COMPARTILHADO — na mesma tarde um outro agente derrubou o login do app
editando este arquivo ao vivo. A correção é de **uma linha** (remover a entrada da allowlist)
e não toca em nenhum caminho de autenticação, mas o arquivo merece revisão de quem cuida da
base antes de virar padrão.

**Regra que fica:** na allowlist entram apenas rotas que um TERCEIRO sem sessão precisa
chamar. Rota administrativa que também confere papel nunca pode entrar — as duas coisas se
anulam e o resultado é 401 permanente que ninguém sabe explicar. Há spec cobrindo isso em
`spec/requests/api/whats/webhook_realtime_spec.rb` ("allowlist pública").

**Dono:** plataforma / base ai9 (gate de autenticação).

# Tasks: S1 — Autenticação e conta

Fila de trabalho do Phase 3 para a fatia **S1**. Ordem por camada: **dados → backend →
frontend → testes → paridade**. Uma tarefa = **um comportamento verificável**. Só se marca
quando o código existe, o teste passa e o `parity-ledger.md` foi atualizado.

Depende de **S0** (papéis + hierarquia C3, `authorize!`, `require_not_readonly!`,
`AuditEvent`, `Pagination`, `DataTable`, `AsyncSection`, `SearchInput`, `Avatar`).

Portões: `cd backend && bundle exec rspec` · `cd frontend && node
node_modules/typescript/bin/tsc --noEmit` (baseline **0 erro**).

## 1. Dados

- [x] 1.1 Migration: colunas de perfil que faltam em `users` (gênero como **enum string**,
      aniversário como **date**, 2 telefones, CNPJ, documento fiscal com **data real**,
      contato de emergência, graduação) — 12 dos 41 campos **já existem**
      (`schema.rb:653-660`). `livetat_auth_user_infos` **não vira tabela**. — **DB-004,
      DB-505, BE-016, BE-507**
- [x] 1.2 Migration `users.blocked_at` (timestamp). Os dois campos concorrentes do legado
      (`is_active`, `deactivated`) colapsam em um. — **DB-002, BE-036**
- [x] 1.3 Migration `users.identifier` (6 caracteres A-Z0-9) com **índice único** e retry na
      geração. Não há padrão a reusar: `smart_id`/`by_any_id` saiu no trim. — **BE-048**
- [x] 1.4 Migration/validações de `users`: `formal` → `name`; **`username` não é portado**;
      unicidade garantida **pelo banco**, não só pela aplicação. — **DB-001, DB-014,
      DB-500, BE-501**
- [x] 1.5 `confiability_level` (Baixa→Média→Alta→Máxima) preservado como regra de negócio;
      o nível "Máxima" passa a ser alcançável de verdade porque o ai9 **verifica telefone**
      (é canal de login). Ver Q-B4/Q-B8. — **DB-015, DB-016**
- [x] 1.6 Avatar por Active Storage com variantes sob demanda (os 5 estilos Paperclip
      `thumb/preview/medium/large/retina` **não** viram 5 arquivos gravados). — **DB-003,
      BE-503**
      · **Entregue pela S13 (OPS-493), conferido aqui.** `config/attachments.yml` declara
      `user.avatar` com 3 MB, `content_types: [png, jpg, jpeg, webp, gif]`, política
      `authenticated` e as variantes `thumb: 80`, `preview: 250`, `large: 1500` —
      **derivadas sob demanda**, nunca gravadas. `User#display_avatar_url` devolve a
      `preview` (250 px), e não o original, porque o avatar aparece em lista.
      Paperclip não é portado: as 4 colunas `avatar_file_*` não são recriadas.
      Verificado renderizando: `/users` mostra o avatar, e o `avatar_url` não contém
      `/uploads/avatars/`.
- [x] 1.7 Confirmar que `client_applications` e `users.provider`/`provider_uid` cobrem
      credencial de máquina e vínculo social **sem tabela nova**; o índice único do vínculo
      **não** inclui `user_id` (o do legado incluía). — **DB-009, DB-010, DB-504, DB-506**
- [x] 1.8 Registrar os `dropped` de dados com evidência: configuração de senha do Devise,
      ETL Django de 2021, ausência de esquema da `auth_ux19`. — **DB-013, DB-017, DB-507**
      · Lançados no `parity-ledger.md`: **DB-013** (não há senha no produto — `grep -r
      encrypted_password backend/` = 0, `bcrypt` não requerido, `devise :omniauthable` e
      nada mais); **DB-017** (o dump de produção de 31/05/2025 é o Safegold em Rails, com
      `livetat_auth_*` — o ETL Django de 2021 não tem objeto aqui); **DB-507** (registro
      de ausência: a `auth_ux19` não tem esquema próprio).
- [x] 1.9 Decidir e registrar o destino de `is_active` e `legacy_password` no ETL (Q-B3:
      default = `is_active = 0` nasce com `blocked_at` preenchido e sai na lista de
      exceções; `legacy_password` **não é migrado**). — **DB-002** (parte ETL)

## 2. Backend — fechar a porta do cadastro público (faça isto primeiro)

- [x] 2.1 **Retirar da allowlist pública** de `backend/app/controllers/api/root.rb:35-46` as
      4 rotas: `pre_register`, `complete_registration`, `visitor_signup`,
      `visitor_signup_with_link`. Sem isso o **D-39 volta sozinho** por uma porta que não
      veio do legado (achado #4 do `migration-map.md`). — **BE-011, FE-003, FE-509**
- [x] 2.2 Desmontar os endpoints correspondentes em `api/auth/v1/registration.rb` — não
      basta tirar da allowlist se a rota continua respondendo a sessão autenticada. Manter
      **apenas** o que o convite (BE-012) precisa. — **BE-011**
- [x] 2.3 Teste de regressão do D-39: as 4 rotas **não** aceitam anônimo e **não** criam
      usuário com papel administrativo. — **BE-011**

## 3. Backend — identidade

- [x] 3.1 `POST /auth/v1/magic_login/request_code`: `login` vira `identifier` (e-mail **ou**
      telefone, DEC-14). Some a senha. Some o corte por
      `minimal_type_to_sign_up_through_web` — a hierarquia mínima passa a ser garantida
      **pelo convite**. — **BE-002, BE-516, BE-020**
- [x] 3.2 Código de acesso: 6 dígitos, **5 min** de vida, 3 tentativas, teto de 5 pedidos /
      15 min por destino normalizado, `SecureRandom` e comparação de tempo constante. O
      token que **nunca expirava** (D-37) morre aqui. — **BE-020, BE-510, BE-522**
- [x] 3.3 `POST /auth/v1/code_validation` + `GET /auth/v1/me` devolvendo `Api::Entities::User`
      (contrato canônico, FE-516). O 401 com **corpo string** vira `{error:, message:}` do
      `ApiResponseHandler`. — **BE-003, FE-516**
- [x] 3.4 Corrigir o **N+1** de `permissions` na entity de usuário
      (`api/entities/user.rb:54-66` dispara uma query por usuário em toda listagem). —
      **BE-003** (IMP-A24)
- [x] 3.5 `GET /auth/v1/magic_link/verify`: consome `link_token` de **uso único** (índice
      único em `login_codes.link_token`) e abre sessão. Não grava senha. — **BE-022, BE-021**
- [x] 3.6 Logout único para web e API: denylista access + refresh + cable e limpa os dois
      cookies HttpOnly; logout de quem já está deslogado continua sem erro. — **BE-005,
      BE-006, BE-517**
- [x] 3.7 `?next=` no pós-login com **allowlist same-origin** (o legado interpolava direto
      no JS — família D-69, open redirect). — **BE-007** (IMP-A3)
- [x] 3.8 OAuth: um callback só, casamento por `(provider, uid)` e depois por e-mail —
      **nunca por `formal`** (nome completo), que fazia homônimo assumir conta alheia.
      `provider_ignores_state: true` **não** é replicado (D-40). — **BE-023, BE-024,
      BE-513, BE-514, BE-512, OPS-007**
- [x] 3.9 Gate central único (`Api::Root#before`) com allowlist **por rota**, no lugar da
      hierarquia `AppRequired`/`UserRequired`/`AppOrUser`. Default = **exigir sessão**. —
      **BE-515, BE-039, BE-038**
- [x] 3.10 Credencial de máquina: `Authorization: Bearer <client_token>` no lugar de
      `X-LAA-Agent`/`X-LAA-Token`; o token de **usuário** permanente do legado morre. O
      token de máquina **não herda papel de OG**. — **BE-047, BE-508, BE-502, OPS-008**
      (IMP-A20, IMP-A30; ver Q-B1)
- [x] 3.11 Registrar os `dropped` de identidade com evidência: config de senha do Devise,
      fluxo custom de senha, rotas/efeitos da engine, controllers Devise vazios. —
      **BE-004, BE-008, BE-019, BE-509, BE-521, BE-523, BE-524, BE-747**
      · Os 8 lançados no `parity-ledger.md`, em três famílias com a evidência de cada uma:
      **senha** (BE-004, BE-019, BE-521), **engine** (BE-509, BE-523, BE-524, BE-747 —
      `grep -rn "Livetat::" backend/app` devolve dois comentários e zero código) e
      **rota catch-all** (BE-008, que fazia endereço errado virar tela de login em vez
      de 404).
## 4. Backend — contas, perfil e bloqueio

- [x] 4.1 `GET /api/v1/users` com a matriz do DEC-18 (OG/Admin CRUD, Gerente R, Colaborador
      sem acesso) no lugar do `require_og!` de `users.rb:70`, **paginação que funciona** e
      busca insensível a acento **dos dois lados** da comparação. — **BE-009, BE-518,
      BE-025** (IMP-A4, IMP-A13)
- [x] 4.2 `GET /api/v1/users/:id`: busca **só por id** (cai o fallback em cascata
      `id`→`username`→`email`→`user_params[:id]`, que dava 500 por `ParameterMissing`);
      autorização pela matriz. — **BE-010**
- [x] 4.3 `POST /api/v1/users` + `POST /api/v1/users/:id/invite`: o usuário nasce com papel
      **explícito** (nunca `Admin` fixo — D-39) e **sem senha**, recebendo convite com magic
      link de primeiro acesso. — **BE-012, BE-519, OPS-001** (IMP-A6)
- [x] 4.4 `PUT /api/v1/users/:id`: some a troca de senha e o duplo update (`@user` +
      `current_user`); ganha autorização de servidor. — **BE-013**
- [x] 4.5 `PATCH /auth/v1/me` (perfil próprio) e `GET /auth/v1/me` estendido; a rota morta
      `show_info` (D-43) não é portada. — **BE-015, BE-016**
- [x] 4.6 `DELETE /api/v1/users/:id` (auto-remoção): a confirmação por **senha** vira
      confirmação por **código enviado ao destino cadastrado**. — **BE-014** (IMP-A7)
- [x] 4.7 `DELETE /api/v1/users/:id` (remoção por administrador): **verifica permissão no
      servidor** (hoje `may_delete_users` só existe na view — D-34) e trata a cascata
      (papel, perfil, participações). — **BE-030**
- [x] 4.8 `POST /api/v1/uploads/avatar` por **Active Storage**: validação do **tipo real** do
      conteúdo e **teto no servidor**. Não reusar `assets_proxy_controller.rb` nem o caminho
      atual de `uploads.rb:38-42`. — **BE-017, OPS-505, OPS-506** (IMP-A9)
      · **O Safegold não usa mais aquele endpoint**: o avatar sai por
      `POST /api/v1/users/:id/avatar` (S13/OPS-493), pelo motor único — ActiveStorage
      privado, magic bytes via Marcel (`spoofing_protection: true`) e 3 MB do catálogo.
      · **O endpoint antigo continua montado e foi ENDURECIDO nesta passada**: ele tem
      **dois consumidores vivos que não são deste produto** (`AIAgentConfigPanel.tsx:226`
      e `FlowSettingsModal.tsx:72`, do assistente interno), então removê-lo quebraria as
      duas telas — Regra de fronteira. Ganhou tipo pelos magic bytes e teto de 3 MB, e
      **só isso**. Medido: `Marcel::MimeType.for(tempfile)` devolve `text/plain` para o
      `fake.png`; passando `name:` devolveria `image/png` e o buraco continuaria aberto.
      · O que **não** foi consertado e vira flag de upstream (`#S1-2`): o arquivo daquele
      endpoint continua indo para `public/uploads/`, servido sem autenticação. Fechar isso
      é mover os dois consumidores para o motor de anexos — **dono: a fatia do chat**.
- [x] 4.9 `POST /api/v1/users/:id/block` e `DELETE .../block`: grava `blocked_at`,
      **denylista o JWT ativo na hora** e audita. — **BE-036, BE-037** (IMP-A15, IMP-A16)
- [x] 4.10 Conta bloqueada é barrada **no gate central** e recebe explicação estruturada, não
      logout mudo. — **BE-038, FE-044** (IMP-A17)
- [x] 4.11 `GET /api/v1/users/validate_cpf`: status HTTP corretos (**422/409**, não 405/406).
      — **BE-035** (IMP-A14)
- [x] 4.12 `GET /api/v1/users/:id/memberships`: listagem **paginada e escopada ao que o
      solicitante pode ver** (o legado fazia `Project.all` sem paginação e sem filtro). —
      **BE-034**
- [x] 4.13 Geração de `identifier` no `before_create`, com unicidade garantida pelo banco. —
      **BE-048** (IMP-A21)
- [x] 4.14 Callbacks do `User` e `UsersService.create` sem `Role` intermediário, sem 17
      abilities clonadas e **sem metaprogramação em runtime**. — **BE-049, BE-506**
      (IMP-A22)
- [x] 4.15 Registrar os `dropped` de conta com evidência (telas/rotas duplicadas da engine).
      — **BE-026** (verificar rota única), **BE-027, BE-028, BE-029** conforme o mapa
      · **⚠ A tarefa estava errada, e o razão registra a correção.** Os quatro são
      `reuse`/`adapt` no `proposal.md`, não `drop` — e as quatro telas **existem**:
      `/users`, `/users/:id`, `/users/new` e `/users/:id/edit`. O que era duplicado no
      legado eram os **pares de rota** (`/u/users` e `/u`; `/u/console/users/add` e
      `/u/users/new`), e a duplicação sumiu porque cada um virou **uma** rota. Lançados
      como `migrated`, com o par colapsado escrito em cada linha. Ver a seção
      "S1 — os 173 IDs lançados" do `parity-ledger.md`.
- [x] 4.16 **DEC-108 — as 7 abilities com efeito real voltam, e as 6 novas passam a ser
      checadas NO SERVIDOR.** — **BE-040, BE-041, BE-042, DB-007, DB-008**
      · O catálogo servia **uma** linha contra as 17 do legado, apoiado numa afirmação
      falsa ("nenhuma é consultada em lugar nenhum do app"). A contagem de call sites reais,
      fora de `ability_factory_decorator.rb` e dos seeds, desmente: o zero valia para **10**,
      não para 16. Cada call site foi **lido** antes de portar.
      · Onde cada uma passou a ser checada, com o call site do legado que a sustenta:
      `may_create_users` → `POST /api/v1/users` (403); `may_invite_users` →
      `POST /api/v1/users/:id/invite` (403); `may_delete_users` → `DELETE /api/v1/users/:id`
      (403, **exceto** auto-remoção, BE-014); `may_modify_public_entries` →
      `POST /api/v1/memberships` e `GET /memberships/candidates` (403, a mesma caixa
      «Adicionar Membro» do legado — a **remoção não**, lá ela estava atrás de
      `user_is_readonly`); `max_users_amount` e `max_invitations_amount` → **422**.
      `user_is_readonly` fica como estava, no `require_not_readonly!` global.
      · **A DEC-30 abre exceção para segurança/autorização**: no legado seis dessas eram
      gate de view (família do **D-34**), e replicar isso seria portar a vulnerabilidade.
      · Os dois `max_*` são **limite**: `permissions.kind` + `default_limit_value`, e
      `limit_value` em `user_type_permissions` e `user_permissions`. `NULL` = sem limite,
      `0` = nenhum permitido — os dois existem no seed do legado.
      · `login_codes.invited_by_id` nasce porque um teto de convites precisa de algo a
      contar; o teto é de convites **em aberto** do próprio ator.
      · Uma divergência deliberada, no `improvements-log.md` (`ABL-S1-03`): **o OG fica sem
      teto**. O seed da engine dava 100/200 ao OG contra 9999 do Admin; com o limite valendo
      de verdade e 135 contas em produção, o fornecedor nasceria bloqueado enquanto o Admin
      do cliente seguiria criando.

## 5. Backend — impersonation auditada

- [x] 5.1 **Trava de hierarquia** em `POST /auth/v1/impersonate/start`: só hierarquia
      inferior. Nunca OG, nunca lateral (DEC-18.3). — **BE-031**
- [x] 5.2 **Motivo obrigatório** + trilha persistida no `AuditEvent` de S0 (quem, quem foi
      personificado, quando, por quê, quando encerrou). — **BE-031, OPS-395**
- [x] 5.3 Sessão personificada **expira** e **não encadeia** (o personificado não
      personifica). — **BE-031**
- [x] 5.4 Corrigir a **ordem das checagens**: 403 **antes** de 404/422
      (`impersonate_service.rb:13-18` vaza existência de usuário). — **BE-031** (IMP-A28)
- [x] 5.5 `POST /auth/v1/impersonate/stop` fecha a trilha (já é no-op seguro quando não há
      impersonation). — **BE-032**
- [x] 5.6 Busca de alvos de impersonation: `GET /api/v1/users?q=&per_page=5`, com
      transliteração **simétrica** nos dois lados da comparação. — **BE-033**

## 6. Backend — e-mail transacional

- [x] 6.1 SMTP por ENV; **`openssl_verify_mode: VERIFY_NONE` não é replicado**, a porta
      passa a ser configurada (D-112) e o TLS verificado (D-85). — **BE-533, OPS-500**
      · **Entregue pela S18 (OPS-626 / C-05), conferido aqui lendo os três arquivos.**
      `config/environments/{development,production}.rb` montam `smtp_settings` inteiro por
      ENV (`SMTP_ADDRESS/PORT/DOMAIN/USERNAME/PASSWORD/AUTHENTICATION/TLS_ENABLED`), e
      `openssl_verify_mode` nasce **`peer`** — o legado desligava `VERIFY_PEER`
      globalmente (`ssl_for_win.rb:1`) e a base ai9 repetia com `'none'`. O
      `.env.example` documenta a mudança de comportamento como intencional.
- [x] 6.2 `ApplicationMailer` + layout com a marca **Safegold** (a base sai hoje com
      `GOAT BY POLEMK` hardcoded — U13, upstream flag; aqui trocamos só o do produto). —
      **BE-535, FE-530**
- [x] 6.3 Os 3 e-mails vivos como **templates ERB** (nunca concatenação de string dentro do
      Ruby), com `.text.erb` ao lado de cada `.html.erb`. — **BE-536, FE-533, FE-534**
- [x] 6.4 E-mail de **convite**: carrega magic link de primeiro acesso e **nenhuma senha**
      (D-38). — **OPS-001, FE-535** (IMP-A6)
- [x] 6.5 E-mail de **código de acesso** por Sidekiq (`deliver_later` → fila
      `<APP_NAME>_mailers`), com o `<title>` correto. — **OPS-002, FE-536, OPS-502**
- [x] 6.6 Anexos inline (logo) lidos **do storage**, não do filesystem do servidor de
      aplicação, e com tratamento de erro (o `File.new(...).read` sem rescue derrubava o
      envio). — **BE-535, OPS-504**
      · **A premissa da tarefa não se aplica: não existe anexo inline no ai9.** Medido:
      `grep -rn "attachments\[" backend/app/mailers backend/app/views` = **0**; no legado
      são 8 pontos em `engines/mailer19/app/mailers/livetat/mailer19/mailing.rb` (mais o
      `avatar.png` do remetente no convite), todos com `File.new(...).read` **sem
      `rescue`**. O `layouts/mailer.html.erb` desenha a marca em **texto**, com o motivo
      escrito no próprio arquivo: imagem remota cai em bloqueio de imagem na maior parte
      dos clientes de e-mail. A regra que a tarefa protege — *falta de imagem de marca não
      derruba envio* — passa a valer **por construção**, não por `rescue`.
      · Registrado como divergência: `OPS-504` = `dropped` com a evidência no razão, e
      `MAIL-02` no `improvements-log.md` para o QA não ler a diferença como regressão.
- [x] 6.7 Registro de entrega: **metadados sem corpo** (remetente, destinatário, assunto,
      status, timestamp) com expurgo de 180 dias — decisão **DS1-3**, pendente de Q-B18. —
      **DB-514**
- [x] 6.8 DKIM assinado **no provedor**, chave fora do repositório, e **rotação obrigatória**
      da chave que estava versionada (D-85) registrada no runbook de cutover — decisão
      **DS1-4**, pendente de Q-B19. — **OPS-501**
      · **Chave fora do repositório: sim.** Medido no legado — `git ls-files lib/ | grep
      dkim` devolve `lib/dkim_private_key.pem`, carregada com `open(...)` no boot em
      `config/application.rb:112`. No ai9 não há `.pem` versionado; a S13 (OPS-485 /
      OPS-608) reescreveu como `Sfg::DkimSigner` + `Sfg::DkimInterceptor`, com
      `DKIM_DOMAIN`/`DKIM_SELECTOR` e a chave em `DKIM_PRIVATE_KEY` **ou** num
      `Credential` de provedor `dkim` (encriptado, DEC-61), resolvida **na hora do envio**
      e não no boot.
      · **Assinado no provedor: é o estado atual, por omissão deliberada.** Sem
      `DKIM_DOMAIN` o interceptor **não faz nada** — que é exatamente o caminho de quem
      deixa o provedor assinar, o default declarado do **Q-89/Q-B19**. O mecanismo do lado
      da aplicação existe e nasce inerte, para o caso de o usuário escolher a opção (b).
      · **Rotação no runbook: sim**, item 2.4, agora com as duas decisões escritas (quem
      assina, e revogar no DNS o seletor `dk` antigo). **Dono da escolha: o usuário.**
- [x] 6.9 Registrar os `dropped` de e-mail com evidência: fachada `GrindMailer`, endpoints
      HTTP `/mailer/**` (código morto), tabela `delayed_jobs`, rake de instalação do runner,
      templates mortos e o e-mail de senha alterada. — **BE-534, BE-537, DB-515, OPS-503,
      OPS-003, OPS-004, FE-529, FE-531, FE-532, FE-537**
      · Os 10 lançados no `parity-ledger.md`. Duas famílias: **engine de e-mail**
      (`GrindMailer`/`Mailing`, `/mailer/**`, `delayed_jobs`, rake do runner, layout e dois
      templates) — substituída por `ApplicationMailer` + Sidekiq + `EmailDeliveryLogger`
      (DEC-90: metadados sem corpo, expurgo de 180 dias); e **e-mail de senha**
      (OPS-003, OPS-004, FE-537), que perdeu o objeto com a DEC-14/DEC-75.
## 7. Frontend — identidade

- [x] 7.1 `/login` como **um** fluxo em etapas (destino → código → completar), com abas
      **E-mail / WhatsApp**. Os três painéis empilhados do legado (Entrar / Cadastre-se /
      Esqueci) somem. — **FE-001, FE-002, FE-004**
- [x] 7.2 Rodapé social do login (Google + Facebook conforme Q-B2 — **ligado, mas não
      anunciado** até o usuário confirmar). — **FE-005**
- [x] 7.3 Aviso do `?next=` visível (o container `.warning_message` do legado está
      **comentado no HTML** — a mensagem existe e nunca aparece). — **FE-006**
- [x] 7.4 `/magic-login`: validação do link, com estado **"link expirado" que renderiza de
      verdade** (no legado é inalcançável — D-123). — **FE-007, FE-010, FE-507**
- [x] 7.5 Barra/metadados das telas de auth com a marca SFG (logo dos tokens do app, não de
      `app_theme` por usuário); o item "Cadastre-se" fica fora (DEC-18.7). — **FE-045,
      FE-501, FE-518**
- [x] 7.6 Erro de logout deixa de ser silenciosamente ignorado. — **FE-039**
- [x] 7.7 Interceptor 401: conta bloqueada **explica o motivo** na tela de login. —
      **FE-044** (IMP-A17)
- [x] 7.8 Registrar os `dropped` de tela de identidade, **um a um com evidência** (telas
      duplicadas de engine, views cruas do Devise, overrides `deface` inertes, SDK do
      Facebook). — **FE-003, FE-008, FE-009, FE-046, FE-047, FE-048, FE-049, FE-500,
      FE-502, FE-503, FE-504, FE-505, FE-506, FE-508, FE-509, FE-510, FE-514, FE-519,
      FE-520, FE-521, FE-522, ENG-auth_omni19**
      · Os 22 lançados no `parity-ledger.md`, em quatro famílias com evidência própria:
      **senha** (FE-008, FE-009, FE-504, FE-505, FE-506, FE-508, FE-514), **cadastro
      público** (FE-003, FE-046, FE-509, FE-510), **engine** (FE-047, FE-048, FE-049,
      FE-500, FE-502, FE-503, FE-519, FE-520, `ENG-auth_omni19`) e **Facebook**
      (FE-521, FE-522). O `ENG-auth_omni19` **não tinha linha no inventário** — foi
      acrescentado numa seção própria do razão, para que a fatia feche.
## 8. Frontend — contas, perfil e permissões

- [x] 8.1 `/users`: **fim do dado falso** — `UsersPage.tsx:14-26,58-68` serve `mockUsers`
      hardcoded para visitor/client em vez de chamar a API. Inaceitável num sistema de
      crédito. — **FE-011** (IMP-A27, U11)
- [x] 8.2 Busca com debounce de 300 ms e reset de página. — **FE-012**
- [x] 8.3 Paginação de desktop na tela de contas, consumindo o `Pagination` de S0 e o
      `X-Total-Count`. — **FE-014**
- [x] 8.4 Card de usuário: papel (OG em destaque), e-mail, "Último login"/"Nunca logou",
      `identifier`, selo de membro padrão e **de conta bloqueada**; iniciais com cor
      determinística. — **FE-015, FE-017, FE-515**
- [x] 8.5 Menu de ações do card (Ver mais / Editar / Ver como / Bloquear / Desbloquear) com
      **os mesmos gates do servidor** — o legado mostrava "Ver como" para qualquer papel na
      lista e só permitia para alguns. — **FE-016**
- [x] 8.6 Drawer de criar/editar com deep-link (`/users/new`, `/users/:id/edit`), **sem
      senha**, com **um** campo de papel (o legado tinha hidden + select coexistindo) e erro
      por campo. — **FE-018, FE-019, FE-021**
      · O drawer é **derivado da URL**, não de um `useState`: `new` e `:id/edit` são rotas
      **filhas** de `/users` no registro de navegação, então o gate de papel da área vale
      para quem digita o endereço, o botão Voltar fecha o drawer, e recarregar em
      `/users/:id/edit` abre o formulário **preenchido** (busca no servidor quando a lista
      ainda não carregou — sem isso o `PATCH` gravaria vazio por cima, falha silenciosa).
      · Erro **por campo**, com `role="alert"` e `aria-invalid`, no lugar do `toast` único
      com as mensagens concatenadas. A resposta do servidor é roteada para o campo certo.
      · Sem senha, e há exemplo que falha se um `type="password"` voltar ao arquivo.
      · Verificado renderizando `/users/new` e `/users/:id/edit`, claro e escuro.
- [x] 8.7 `/users/:id` com abas Geral / Projetos gateadas **no mesmo lugar** (no legado a
      aba e o conteúdo eram gateados em linhas diferentes e o Gerente via aba vazia);
      "Editar" gateado por permissão de **editar**, não de remover. — **FE-022, FE-023**
      · Tela nova: `frontend/src/app/pages/users/UserDetailPage.tsx`, com **três** abas
      (Geral / Projetos / Permissões). A correção do gate é estrutural: **nenhuma aba tem
      condição de visibilidade própria** — quem chega já passou pelo gate de papel do
      registro de navegação, e o que muda entre papéis é o poder de **escrever**, decidido
      uma vez em `podeEscrever`. Não existe o lugar onde alguém esconderia a aba e
      esqueceria do conteúdo.
      · "Editar" usa o gate de escrita da matriz (DEC-18), o mesmo do `PUT` do servidor.
      · Verificado renderizando, claro/escuro e 390×844.
- [x] 8.8 Aba Projetos de `/users/:id`: lista **paginada e escopada**, DELETE pela rota com
      `:id` de verdade, erro visível. — **FE-025**
      · Paginada (`GET /api/v1/users/:id/memberships`, `PaginationPill`), escopada pela
      interseção alvo × solicitante (C1), com carregando / vazio / erro. Verificado
      renderizando: a aba lista os dois projetos reais da conta.
      · **⚠ SEM o DELETE, e é deliberado.** A **DC-18** (S4, decisão posterior a esta
      tarefa) definiu a aba como **informativa**: conceder e revogar participação é da aba
      «Membros» **do projeto**, onde valem as três condições de servidor do **DEC-18.5**
      (não-readonly, não remover o dono, não remover a si mesmo). Um segundo lugar para
      revogar seria essas condições reimplementadas — foi assim que o legado chegou ao
      D-34. O defeito que a tarefa cita (o backend ignorava o `:id` e usava a trinca) está
      fechado do lado certo, em `DELETE /api/v1/memberships/:id`. A divergência está no
      `parity-ledger.md` e num comentário na própria tela.
      · **Duplicação registrada para o orquestrador:** `GET /api/v1/users/:id/projects`
      (S4/BE-100, sem paginação) e `GET /api/v1/users/:id/memberships` (S1/BE-034,
      paginado) respondem à mesma pergunta. Não colapsei — `BE-100` é ID de outra fatia
      (C4).
- [x] 8.9 `/profile`: perfil próprio completo, e-mail e código somente leitura, máscara de
      CPF que **não trava o formulário inteiro** quando inválida, máscara dinâmica de
      telefone 8/9 dígitos, copiar código, aceite de Termos com a trava **funcionando**
      (`if (jbb.val()==false)` nunca era verdadeira), FAB de salvar só com alteração
      (`PATCH` só dos campos alterados). — **FE-028, FE-029, FE-030, FE-031, FE-034,
      FE-035, FE-033**
      · **Completo:** os seis campos estendidos do DEC-74 (gênero como enum, aniversário
      e emissão do documento fiscal como `date`, CNPJ, documento fiscal, escolaridade)
      entraram na tela. **Achado no caminho:** o `PATCH /auth/v1/me` já os aceitava e a
      **entity não os expunha** — a tela gravava e, ao recarregar, voltavam vazios. Meia
      fronteira, corrigida em `Api::Entities::User`.
      · **Código** (`identifier`) e **e-mail** em leitura, com botão de copiar no código e
      o motivo escrito em cada um. O código existia no banco e **não aparecia em lugar
      nenhum** da tela de perfil.
      · **CPF não trava mais o formulário:** a validação virou um mapa por campo. Antes
      um `validate()` devolvia **uma** string e abortava o `save` inteiro — documento
      antigo mal gravado impedia de corrigir o endereço.
      · Telefone pelo `PhoneInputGroup` (máscara 8/9 dígitos, DDI/DDD), **editável mesmo
      com o telefone confirmado** (DEC-74: a trava do legado não é replicada).
      · Aceite de Termos: `MyTermsSection` (S12/DEC-66), já com a trava funcionando.
      · FAB só com alteração e `PATCH` só dos campos sujos — `email` e `avatar_url` ficam
      fora da lista, cada um com seu motivo no código.
      · Verificado renderizando, claro/escuro e 390×844.
- [x] 8.10 Exclusão da própria conta: modal de confirmação **de verdade** + código
      (o legado gateava por `may_create_users?` e não tinha modal). — **FE-033**
      · Bloco "Encerrar minha conta" em `/profile`, em dois passos: pedir o código (o
      **mesmo** código de acesso, `POST /auth/v1/magic_login/request_code`) e digitá-lo. O
      `DELETE /api/v1/users/:id` só apaga com um `LoginCode` válido e não usado, que é
      consumido no ato. Conta dona de projeto responde **409** com a instrução de
      transferir a propriedade antes. Ao final, `logout()` de verdade: limpar só o estado
      local deixaria os cookies HttpOnly vivos.
- [x] 8.11 Painel de permissões em `/users/:id`: das 17 abilities sobra **uma**
      (`user_is_readonly`); as 12 condicionais que não gateiam nada somem. — **FE-024,
      FE-513**
      · Aba "Permissões" do detalhe, consumindo `GET /api/v1/users/:id/permissions` e
      `PUT .../permissions/:key` (BE-018 — o `:id` **manda**, que é a correção do D-34).
      A tela renderiza o **catálogo do servidor**, sem lista escrita nela: hoje é uma
      linha, e a segunda aparece sozinha no dia em que existir.
      · Alvo fora do alcance de hierarquia recebe 403 `HIERARCHY_LOCKED` e a tela mostra
      um estado explicativo — "existe e você não pode mexer" é informação diferente de
      "não existe".
      · FE-513: a tela **diz** o que sumiu, para quem vem do legado procurar as outras
      dezesseis não abrir chamado.
- [x] 8.12 Tela `/permissions` (um card por papel) com toggle por papel que **não exige
      recarregar**: `PermissionsChannel` empurra e o React Query invalida (Princípio 10).
      A mudança passa a ter efeito imediato. — **FE-026, FE-027, BE-040** (IMP-A18)
      · Tela nova: `frontend/src/app/pages/users/PermissionsPage.tsx`, montada no registro
      de navegação (o item existia com `element: null` — menu apontando para o nada).
      · **`PermissionsChannel` estava furado e foi corrigido**: a versão da base fazia
      `stream_for("permissions:#{params[:user_id]}")` com o `user_id` **que o cliente
      mandasse**. Agora o fluxo é sempre o do usuário da conexão, pedir o de outra pessoa
      é `reject`, e a emissão tem ponto único (`publish_changed` /
      `publish_user_type_changed`). É a flag **U2**, e dois canais desta migração já a
      tinham recusado por escrito. 5 exemplos em `spec/channels/permissions_channel_spec.rb`.
      · **Verificado renderizando como Admin:** o card do próprio papel vem com o toggle
      desabilitado e "Somente leitura para o seu papel"; Gerente e Colaborador editáveis;
      o card do OG **não aparece** (filtro de hierarquia do servidor). É o DEC-18.2 na
      tela. Também conferido em 390×844.
- [x] 8.13 Toasts de sucesso **e** de erro nas duas telas (na tela de permissões do legado o
      branch `else` era vazio: não havia toast de sucesso). — **FE-042, FE-043**
      · Nas duas: `/permissions` (por papel) e a aba Permissões de `/users/:id` (por
      pessoa). O sucesso diz o que mudou **e que vale agora para quem já existe** — que é
      a informação que o legado não tinha como dar, porque lá a permissão era clonada no
      usuário (D-35). O erro distingue `HIERARCHY_LOCKED` do resto.
- [x] 8.15 **DEC-108 na tela**: as 7 permissões aparecem, as 2 de limite viram campo
      numérico, e a docstring deixa de atribuir ao usuário uma decisão do orquestrador. —
      **FE-024, FE-026, FE-027, FE-042, FE-043**
      · A tela **não tem lista escrita dentro dela**: passou de 1 para 7 no instante em que
      o servidor passou a devolver 7, sem uma chave digitada em `PermissionsPage.tsx`.
      · O que precisou mudar foi o **tipo**: `PermissionControl` (novo, compartilhado pelas
      duas telas que editam permissão) renderiza toggle **ou** teto conforme o `kind` que o
      servidor manda. Num teto, **vazio = sem limite** e **0 = nenhum permitido**; grava no
      `blur`/Enter, não a cada tecla — digitar "50" gravaria "5" e depois "50", com duas
      entradas na trilha e um estado intermediário real no banco.
      · O toast de um limite diz o número, não "Concedida": um teto não é concedido.
      · **Atribuição corrigida.** A docstring citava *"DEC-18.6, decisão #6 do usuário"* — a
      DEC-18.6 é sobre `Membership.role` (outro assunto) e a decisão #6 foi do
      **orquestrador**. A docstring nova cita a DEC-108 e diz o que estava errado antes.
      · `editable` continua vindo do servidor; a tela **não recalcula hierarquia**.
      · `PermissionsChannel` inalterado: continua sendo evento que invalida a consulta,
      nunca polling.
- [x] 8.14 Chip/menu do usuário com "Ver como" (OG **ou** Admin, DEC-18.3), faixa persistente
      de "Vendo como" e autocomplete de impersonation com debounce e badges de papel
      (limite 5, layout mobile) — revive `ImpersonateSearch.tsx`, hoje morta. — **FE-036,
      FE-037, FE-038**
      · **`useRole()` dizia `canImpersonate: isOg`** — o Admin tinha o poder no servidor e
      **nenhuma porta na tela**. Corrigido para OG **ou** Admin, com teste que chama o
      hook de verdade.
      · **"Ver como…" entra no menu do usuário**, e não só no cartão dos widgets: o cartão
      só aparece com a barra expandida, e a barra **nasce recolhida**.
      · **`ImpersonateSearch.tsx` estava mesmo morta** (nenhum consumidor) — o
      `ImpersonateSelector` tinha uma segunda busca escrita à mão ao lado. Agora é **uma**:
      debounce de 300 ms, teto de **5**, selos dos **quatro** papéis reais (a versão morta
      rotulava todo mundo como "Cliente", papel que a DEC-41 removeu), alvo de toque de
      44 px e a própria conta fora da lista.
      · **Faixa persistente**: `features/auth/ImpersonationBanner.tsx`, no `Layout`. O
      aviso vivia só na barra lateral, que nasce recolhida e **não existe no telefone** —
      quem personificava no celular não via nada. Não pode ser dispensada. O cartão
      duplicado da barra lateral saiu no mesmo passo.
      · **Verificado executando o ciclo inteiro**: menu → busca → motivo → impersonar →
      faixa "Vendo como Tereza Machado — … iniciado por Leonidas" → "Voltar a ser eu" →
      de volta como OG, faixa some.
- [x] 8.15 Registrar os `dropped` de tela de conta com evidência. — **FE-013, FE-020,
      FE-032, FE-511, FE-512, FE-517, FE-047**
      · Seis lançados como `dropped` com evidência (FE-020 e FE-032 são senha; FE-511,
      FE-512, FE-517 e FE-047 são telas da engine).
      · **⚠ `FE-013` não é `dropped`.** É "filtro por tipo de usuário", `adapt` no
      `proposal.md`, e **está na tela**, com os quatro papéis do Safegold. Lançado como
      `migrated`. Ver a seção de contradições do `parity-ledger.md`.
## 9. Testes

### 9.1 Hierarquia (C3) — **sempre os dois lados**

- [x] 9.1.1 Admin **NÃO** personifica OG · Admin **NÃO** personifica outro Admin (lateral) ·
      Admin **PERSONIFICA** Colaborador. — **BE-031**
- [x] 9.1.2 Admin **NÃO** edita permissão de OG · Admin **EDITA** permissão de Colaborador
      (pela tela de `/users/:id`). — **BE-018**
      · Contrato travado em `spec/requests/api/v1/permissions_hierarchy_spec.rb`, no
      **mesmo endpoint que a tela usa** (`PUT /api/v1/users/:id/permissions/:key`): 403
      `HIERARCHY_LOCKED` para o OG com `UserPermission.where(user: og)` vazio, 200 para o
      Colaborador com `readonly_access?` virando `true`. A tela que faltava (aba
      Permissões de `/users/:id`) foi entregue na 8.11.
- [x] 9.1.3 Gerente **NÃO** alcança `/permissions` · Admin alcança. — **BE-040, FE-026**
      · **Servidor:** `permissions_hierarchy_spec.rb` — 403 para o Gerente no catálogo e
      no `PUT`, 200 para o Admin.
      · **Tela:** `src/app/__tests__/permissoes-gate.test.tsx`, três exemplos, um para
      cada forma de chegar na área — o **registro** (`roles: ['og','admin']` e
      `element` não-nulo), o **menu** (`filtrarGrupos` esconde do Gerente) e o **endereço
      digitado à mão** (`RoleRoute` redireciona o Gerente e deixa o Admin passar).
      Testar só um lado repetiria o erro do legado, onde a autorização vivia só na view.
- [x] 9.1.4 O filtro de usuários de um Gerente **NÃO** devolve OG nem Admin · **devolve**
      Colaborador. — **BE-025**
- [x] 9.1.5 Impersonation **não encadeia**: o personificado **NÃO** consegue personificar ·
      o personificador consegue encerrar. — **BE-031, BE-032**

- [x] 9.1.6 **DEC-108** — cada uma das 6 abilities que voltaram prova o **403** (ou 422, nos
      dois limites) **e** o caminho permitido, no mesmo endpoint que a tela chama. —
      **BE-040, BE-042**
      · `spec/requests/api/v1/abilities_enforcement_spec.rb`, 12 exemplos. Sempre os dois
      lados: um teste que só verifique "a checagem existe" passa com ela apontando para o
      lado errado — a armadilha que a DEC-41 já nomeou para a hierarquia.
      · Cobre as duas fronteiras fáceis de errar: a **auto-remoção** não passa por
      `may_delete_users` (BE-014, senão o Colaborador não sai do sistema) e
      `may_modify_public_entries` **não** gateia a remoção de membro.
      · Cobre `NULL` (sem limite) **contra** `0` (nenhum permitido) — confundi-los inverte a
      permissão — e o convite **usado** liberando a vaga do teto.
      · **Verificado EXECUTANDO** contra o servidor de dev em `127.0.0.1:3000`, com sessão
      real de Admin e de Gerente. Os códigos observados estão no relatório da tarefa; o
      catálogo devolveu 7 linhas com `kind`, o Gerente levou 403 no catálogo, e cada
      ability respondeu 403/422 sem a concessão e 200/201 com ela.

### 9.2 Cadastro público (D-39)

- [x] 9.2.1 `POST /auth/v1/pre_register` e `POST /auth/v1/complete_registration` **não**
      atendem anônimo. — **BE-011**
- [x] 9.2.2 `POST /auth/v1/visitor_signup` e `visitor_signup_with_link` **não** atendem
      anônimo. — **BE-011**
- [x] 9.2.3 Nenhum caminho cria usuário com papel administrativo sem convite emitido por
      quem tem permissão. — **BE-012**

### 9.3 Sessão, bloqueio e escopo

- [x] 9.3.1 Bloquear conta **revoga a sessão ativa na hora** (o access token deixa de
      funcionar) e o usuário vê a explicação. — **BE-036, BE-038**
- [x] 9.3.2 Código de acesso: expira em 5 min · 3 tentativas · teto de pedidos · comparação
      de tempo constante. — **BE-020**
- [x] 9.3.3 `link_token` é de **uso único** — o segundo uso falha. — **BE-022**
- [x] 9.3.4 Redirect pós-login só aceita destino **same-origin**. — **BE-007**
- [x] 9.3.5 OAuth **não** casa conta por nome completo (homônimo não assume conta alheia). —
      **BE-514**
- [x] 9.3.6 A aba Projetos de `/users/:id` só devolve o que o solicitante pode ver (C1). —
      **BE-034**
- [x] 9.3.7 Upload de avatar rejeita arquivo cujo **conteúdo real** não é imagem, mesmo com
      `content_type` forjado, e respeita o teto **no servidor**. — **BE-017**
      · As duas metades, em `spec/requests/api/v1/attachments_spec.rb`: o exemplo do
      conteúdo forjado já existia (`fake.png` enviado como `image/png` → 422
      `ATTACHMENT_REJECTED`); **o do teto foi acrescentado aqui** — arquivo com cabeçalho
      PNG real e enchimento acima de `max_size_bytes` é recusado com o número do catálogo
      na mensagem, e o avatar não fica anexado. O exemplo é montado a partir do próprio
      `config/attachments.yml`, então mudar o limite não deixa o teste mentindo.
      · O endpoint antigo da base ganhou os mesmos dois exemplos em
      `spec/requests/api/v1/uploads_spec.rb`.
- [x] 9.3.8 Serialização de usuário **sem N+1** (contagem de queries estável ao crescer a
      lista). — **BE-003**

### 9.4 Frontend

- [x] 9.4.1 A tela de contas **nunca** renderiza `mockUsers` — o teste falha se o mock
      voltar. — **FE-011**
- [x] 9.4.2 O fluxo de login em etapas funciona nas duas abas (e-mail e WhatsApp). —
      **FE-002**
      · `src/features/auth/__tests__/AuthFlow.duas-abas.test.tsx`, 5 exemplos, com o
      `useAuth` e o store **de verdade** — só a borda de rede é mockada. O teste que já
      havia mockava o hook inteiro e provava só que a tela renderiza.
      · **Defeito achado e corrigido pelo teste:** `MagicLogin.handleSubmit` tinha três
      pré-checagens que davam `return` seco com um `console.warn` e o comentário *"a
      validação já é feita no hook"* — **e o hook não era chamado nesses casos**. Na aba
      **WhatsApp**, número curto deixava a tela idêntica: sem mensagem, sem avanço. (Na
      aba E-mail o estrago era menor por sorte do `<input type="email">`, cuja validação
      nativa barra antes do `submit`.) As três cópias saíram; quem valida é o `useAuth`,
      que escreve o motivo na faixa vermelha. Registrado como **IMP-A32**.
- [x] 9.4.3 Estado "link expirado" do magic link renderiza. — **FE-010**

## 10. Paridade e registro

- [x] 10.1 Ledger: os `dropped` desta fatia com a evidência da linha do mapa (≈50 IDs,
      listados nas tarefas 3.11, 6.9, 7.8, 8.15 e 1.8).
      · **55 IDs** lançados como `dropped`, cada um com evidência, em cinco famílias:
      senha (17), cadastro público (5), engine (17), Facebook/OmniAuth (5), e-mail (6) e
      três avulsos (rota catch-all, ETL Django, ausência de esquema). Mais `OPS-504`
      (anexo inline) e `DB-544` (tabela de provedor social, com a contagem de 0 linhas em
      produção exigida pela F.6).
- [x] 10.2 Ledger: os demais IDs de S1 para `migrated`.
      · **Os 173 IDs do `proposal.md` estavam TODOS em `pending`** quando esta passada
      começou — as tarefas 10.1 e 10.2 nunca tinham sido feitas. Somando os **5 órfãos do
      Phase 2** (`DB-540`, `DB-541`, `DB-543`, `DB-544`, `OPS-604`), o `OPS-501` e **cinco
      que o `tasks.md` cita e o `proposal.md` não tabelava** (`BE-012`, `BE-016`, `BE-033`,
      `BE-049`, `DB-514` — todos entregues e todos ainda `pending`), a fatia tem **185
      linhas**: **130 `migrated`** e **55 `dropped`**, com alvo, teste e nota em cada uma.
      Nenhum `verified`: isso é Phase 4. O `ENG-auth_omni19` não tinha linha no inventário
      e ganhou uma. **Conferido por script: zero ID citado no `tasks.md` continua `pending`.**
- [x] 10.3 `improvements-log.md`: IMP-A1, IMP-A2, IMP-A3, IMP-A4, IMP-A5, IMP-A6, IMP-A7,
      IMP-A8, IMP-A9, IMP-A12, IMP-A13, IMP-A14, IMP-A15, IMP-A16, IMP-A17, IMP-A20,
      IMP-A21, IMP-A23, IMP-A24, IMP-A26, IMP-A27, IMP-A28, IMP-A30 — marcando as
      **observáveis**.
      · Faltavam **seis** (A4, A5, A8, A9, A26, A30) — foram escritas. A16 já estava
      junto da A15. E entraram **cinco novas desta passada**: `IMP-A32` (o botão que não
      fazia nada na aba WhatsApp), `IMP-A33` (a faixa de "Vendo como" em toda largura),
      `IMP-A34` (o Admin ganha a porta de "Ver como"), `IMP-A35` (o canal de permissões
      deixa de aceitar `user_id` alheio) e `MAIL-02` (a marca do e-mail vira texto).
- [x] 10.4 `upstream-flags.md`: U4 (`find_by_whatsapp` sem `require_og!`), U5, U6, U13.
- [x] 10.5 **Aviso ao usuário antes da demo** (não é tarefa de código): quem entra hoje
      digitando senha vai digitar um código. DC-01/IMP-A1.
      · Escrito na seção **2b** do `platform-runbook.md` — "Avisos que precisam chegar às
      PESSOAS antes da apresentação" —, com cinco itens e o porquê de cada um: o código no
      lugar da senha, o fim do auto-cadastro, o `username` que identifica mas não recebe,
      o bloqueio que derruba a sessão na hora, e o "Ver como" que pede motivo e fica na
      trilha. Foi para o runbook porque é lá que se procura antes de operar; num
      `tasks.md` fechado ninguém acharia.
- [x] 10.6 Levar as pendências ao usuário: Q-B1, Q-B2, Q-B3, Q-B4, Q-B5, Q-B7, Q-B18, Q-B19
      — todas seguem pelo default declarado se não houver resposta.
      · **As oito já foram levadas e fechadas na Rodada 1** (117 perguntas, zero em
      aberto). O de-para está em `perguntas-rodada-1-mapas.md`: Q-B1→**Q-75** (headers
      `X-LAA-*`, default (a), virou DEC-58) · Q-B2→**Q-45** (Facebook, DEC-44) ·
      Q-B3→**Q-46** (`is_active`/`legacy_password` no ETL, default (a): nasce bloqueado e
      vai para revisão humana) · Q-B4 e Q-B8→**Q-48** (indicador de verificação, DEC-74) ·
      Q-B5→**Q-49** (storage, DEC-76) · Q-B7→**Q-47** (`username`, DEC-45 — e o dump
      mediu: 0 de 135) · Q-B18→**Q-88** (log de e-mail, DEC-90) · Q-B19→**Q-89** (DKIM,
      default (a): provedor).
      · **A única que ainda muda alguma coisa é a Q-89**, e está na seção 2 do runbook
      como item de cutover — ver a tarefa 6.8. **Dono: o usuário.**
## Fechamento de órfãos do Phase 2 — esquema de identidade

Cinco IDs que não tinham dono e passam a ser desta fatia. Ver a seção correspondente do
`proposal.md`.

- [x] F.1 Migration `add_safegold_columns_to_users`: `legacy_id` (**único**), `manager_id`
      (auto-relação), `default_project_id`, `app_theme_id`, `is_default_member`, `kind`,
      `identifier`, `color`. Índices em `manager_id`, `app_theme_id`, `default_project_id` —
      que o legado não tinha. **Fecha: DB-540.**
- [x] F.2 Registrar em `improvements-log.md` que **quem entrava com senha passa a entrar por
      link/código** — mudança observável, decidida, não regressão. **Fecha: DB-540 (parte).**
      · É a linha **IMP-A1** (`[observável]`), com a decisão (DEC-14) e o que o usuário
      vai notar. Acompanhada de `IMP-A2` (`username` continua servindo para entrar) e
      `IMP-A6` (o convite carrega magic link, nunca senha). O aviso operacional
      correspondente está na seção 2b do runbook (tarefa 10.5).
- [x] F.3 Tabela `user_profiles` 1:1 com `users`, recebendo o que não cabe em `users`
      (telefones país/DDD/número e demais campos de `user_infos`). **Fecha: DB-541.**
- [x] F.4 Estender `client_applications` (que **já existe** na base, com domínio próprio) em
      vez de criar uma segunda tabela. Verificável: há **uma** tabela de aplicação cliente.
      **Fecha: DB-543.**
- [x] F.5 Confirmar que o vínculo OAuth usa `users.provider` + `users.provider_uid` com o
      índice único parcial da base, e que **nenhuma** tabela de provedor é criada. **Fecha:
      DB-544.**
- [x] F.6 Tarefa de ETL: **contar** as linhas de `livetat_auth_omni_providers` na origem e
      registrar a contagem como evidência **antes** de o descarte entrar no ledger. **Fecha:
      DB-544 (parte).**
      · **Contagem medida: 0 linhas.** Fonte: `analise-dump-producao.md` §6, sobre o dump
      `sfg-31-may-25.sql` de 31/05/2025 — a mesma leitura que confirmou `pictures`,
      `delayed_jobs` e `geolocations` também vazias. A contagem está **na linha
      `DB-544` do razão**, antes do descarte, que era a exigência da tarefa: nada se
      perde na carga porque não há o que carregar.
- [x] F.7 Configuração do engine de autenticação vira ENV + seed; nenhuma configuração de
      engine sobrevive como arquivo. **Fecha: OPS-604.**
      · **Verificável, e verificado:** `grep -rn "Livetat::\|AuthUx19\|Mailer19\|AuthOmni19"
      backend/app backend/config backend/lib` devolve **dois comentários e zero código**.
      · O de-para completo dos **quatro** blocos `configure do |c|` de
      `config/application.rb:61-116` (25 chaves) está no `parity-ledger.md`, seção
      "S1/F.7", com o destino de cada uma: ENV, seed, ou descartada **com o motivo**
      (limites `max_*` que se contradiziam, rótulos genéricos da engine, cores de tela em
      configuração de servidor, `minimal_type_to_sign_up_through_web` que era o D-39).


---

## Estado ao fim da SEGUNDA passada — 26/08/2026 (quitação da dívida, DEC-101)

**108 de 108.** A primeira passada fechou em **76 de 108** e a DEC-101 mandou parar de
aceitar isso: *"esqueça o prazo … vamos focar e fazer a migração bem"*. As 32 que faltavam
estão acima, cada uma com a evidência do que foi **medido** — não do que foi suposto.

### Como a seção anterior desta fatia estava errada, e em quê

A nota de fechamento de 25/08 dizia **74 de 108**; o arquivo tinha **76**. E dizia que o
`ReasonDialog` e o `ImpersonateSearch` "estão vivos": o `ReasonDialog` estava, o
**`ImpersonateSearch.tsx` não tinha um único consumidor** — havia uma segunda busca escrita
à mão dentro do `ImpersonateSelector`. Fica registrado porque nota de fechamento errada é
como dívida some do radar.

### O que veio de outras fatias e só precisou ser CONFERIDO

Quatro tarefas estavam abertas por escopo que outra fatia já tinha entregue. Nenhuma foi
marcada por leitura de `tasks.md` alheio — todas foram conferidas no código e no comportamento:

| Tarefa | Quem entregou | O que eu conferi |
| ------ | ------------- | ---------------- |
| **1.6 / 4.8 / 9.3.7** (avatar) | S13, `OPS-493` | Catálogo, variantes sob demanda, magic bytes e teto, com os specs rodando. **Acrescentei** o exemplo do teto e endureci o endpoint antigo da base |
| **6.1** (SMTP por ENV) | S18, `OPS-626` | Os dois `config/environments`, `openssl_verify_mode: peer` por default e o `.env.example` |
| **6.8** (DKIM) | S13, `OPS-485/608` | **Aqui eu tinha escrito errado primeiro.** Um `grep` filtrado me devolveu vazio e cheguei a registrar que "não há DKIM no ai9". Há: `Sfg::DkimSigner` + `Sfg::DkimInterceptor`, chave por ENV ou `Credential`, **inerte sem `DKIM_DOMAIN`**. O razão e o runbook foram corrigidos |

### Defeitos achados nesta passada (nenhum deles estava na lista)

1. **O botão "Entrar" não fazia nada, em silêncio, na aba WhatsApp** — três pré-checagens
   com `return` seco e o comentário "a validação já é feita no hook", **e o hook não era
   chamado**. `IMP-A32`.
2. **`useRole().canImpersonate` era só `isOg`** — o Admin tinha o poder no servidor
   (DEC-18.3) e nenhuma porta na tela. `IMP-A34`.
3. **A faixa de "Vendo como" só existia dentro da barra lateral**, que nasce recolhida e
   não existe no telefone. `IMP-A33`.
4. **`PermissionsChannel` assinava o fluxo do `user_id` que o cliente mandasse** (flag
   **U2**) — e a tarefa 8.12 depende justamente desse canal. `IMP-A35`.
5. **`POST /api/v1/uploads/avatar` da base** confiava no `Content-Type` declarado e não
   tinha teto nenhum (flag **F-09**, agora `#S1-2`).
6. **Os seis campos do perfil estendido eram aceitos pelo `PATCH` e não expostos pela
   entity** — a tela gravava e, ao recarregar, voltavam vazios. Meia fronteira.
7. **O indicador de verificação saía como `media`** (valor cru) no detalhe da conta, porque
   a tabela de rótulos vivia só em `/profile`.
8. **`ImpersonateSearch.tsx` rotulava todos como "Cliente"** — papel que a DEC-41 removeu.
9. **Não dava para APAGAR um campo do perfil.** `Auth::MeService#update` tinha um
   `params.slice(...).compact`, e o `.compact` descartava o `nil` **explícito** — que é como
   o cliente diz "apague isto". Medido contra o servidor de dev: `{"graduation": null}` →
   `422 Nenhum campo para atualizar`, e `{"birthday": ""}` também (o Grape converte data
   vazia para `nil`). **Campo de data não tinha como ser limpo**, e nada acusava. `IMP-A36`,
   com quatro exemplos que voltam a falhar se o `.compact` retornar.

### Três lugares onde este `tasks.md` contradiz o `proposal.md` da própria fatia

Escritos por extenso na seção "S1 — os 173 IDs lançados" do `parity-ledger.md`. Em resumo:
**4.15** listava `BE-026`…`BE-029` como `dropped` e eles são `reuse`/`adapt` (as quatro
telas existem); **8.15** listava `FE-013` como `dropped` e o filtro está na tela;
**8.8** pede um DELETE que a **DC-18** (posterior, da S4) decidiu que não vai existir ali.
Onde houve divergência valeu o `proposal.md` e o código que existe.

### O que ficou aberto — e quem é o dono

**Nada desta fatia.** Duas coisas seguem em aberto **fora** dela, e estão escritas onde se
opera:

| Pendência | Onde está | Dono |
| --------- | --------- | ---- |
| **Quem assina DKIM** — provedor (default do Q-89, e é o estado atual porque o interceptor nasce inerte) ou aplicação. E **revogar no DNS o seletor `dk` antigo**, que é obrigatório nos dois casos | `platform-runbook.md` §2, item 4 | **usuário** |
| **A duplicação de endpoint** `users/:id/projects` (S4/BE-100) × `users/:id/memberships` (S1/BE-034) — mesma pergunta, duas fatias | `parity-ledger.md`, seção S1 | **orquestrador**, quando as duas fatias fecharem (C4) |
| `public/uploads/` do endpoint antigo continua servido sem autenticação | `upstream-flags.md` `#S1-2` | **fatia do chat** (é dela que são os dois consumidores) |

### Um erro meu, e a regra que sai dele

Escrevendo o spec do `POST /api/v1/uploads/avatar` eu pus um `after` com
`Dir.glob(Rails.root.join('public/uploads/avatars/*')).each { FileUtils.rm_f }` — e ele
**apagou 19 arquivos versionados** do repositório na primeira execução. A suíte roda com o
`Rails.root` do app: aquele diretório é o de verdade, não um sandbox. Restaurado com
`git checkout -- backend/public/uploads/` (22 arquivos de volta, working tree limpo) e o
hook agora tira a lista **antes** do exemplo e remove só a diferença.

**A regra, para quem escrever o próximo spec de upload:** limpeza de spec nunca varre
diretório — ela remove **o que o próprio exemplo criou**. Vale para
`public/uploads/`, `storage/` e qualquer caminho sob `Rails.root` que não seja `tmp/`.

### Portões (26/08/2026)

Todos em **banco próprio** (`sfg9_s1_test`, `DATABASE_URL` dedicada, apagado ao fim), e a
suíte inteira rodada **uma por vez** — a armadilha do checkpoint é real: dois `rspec` no
mesmo banco travam e o vermelho não é sinal.

| Portão | Resultado | O que não é meu |
| ------ | --------- | --------------- |
| `rspec` (suíte inteira, rodada final e limpa) | **2291 exemplos, 1 falha, 2 pending** | A única falha é `Demo::Orchestrator#run` (**S20**, o escritor de `receivable_entries` — "Autor não pode ficar em branco"). Não toca identidade. Numa rodada anterior havia uma segunda, `login_attempt_spec` *"detects rapid attempts"*, que **passa isolado (15/15)** e não voltou nesta: é a falha intermitente que o checkpoint descreve, dependente de janela de tempo sob máquina carregada |
| `rspec` de S1, depois da última mudança de backend | `spec/requests/api/auth` + `spec/services/auth` = **88 exemplos, 0 falhas**; `uploads_spec` 4/4; `attachments_spec` 13/13; `permissions_hierarchy_spec` 12/12; `permissions_channel_spec` 5/5; `users_account_lifecycle_spec` 26/26; `user_spec` 40/40 | — |
| `zeitwerk:check` | **All is good!** | — |
| `tsc --noEmit` | **0 erros** | — |
| `vitest` (as minhas árvores: `src/app`, `src/features/auth`, `src/components`) | **259 exemplos, 0 falhas** em 33 arquivos | Numa rodada da suíte completa, 2 testes da **S12** (`helpCenterPage`, `helpItemEditor`) estouraram o timeout de 5 s sob contenção; **passam isolados**, conferido |

**Renderizado e executado** — o portão que vale —, claro e escuro, 1440×900 e 390×844:

- **login de ponta a ponta**, com código real de 6 dígitos, sem senha em lugar nenhum;
- `/users`, `/users/new` (drawer de criação, papel nascendo Colaborador, nenhum campo de
  senha), `/users/:id/edit` (**abre preenchido a partir da URL**);
- `/users/:id` com as **três abas exercitadas por clique** — Geral, Projetos (dois projetos
  reais, paginado e escopado) e Permissões;
- `/permissions` como **OG** e como **Admin**: o Admin vê o card do próprio papel com o
  toggle **desabilitado** e "Somente leitura para o seu papel", edita Gerente e Colaborador,
  e **o card do OG não aparece**. É o DEC-18.2 na tela;
- o **toggle exercitado de verdade**: ligar → toast *"Concedida para Gerente. Vale agora
  para quem já existe."* → desligar → toast de revogação. **Estado do banco devolvido ao
  inicial** (conferido: `UserTypePermission` de `gerente` de volta a `granted: false`);
- `/profile` inteiro, incluindo o bloco **"Encerrar minha conta"** aberto, com o destino do
  código nomeado e o campo de 6 dígitos;
- o **ciclo inteiro de impersonação**: menu do usuário → busca com selo de papel → diálogo
  de motivo → faixa *"Vendo como Tereza Machado — … iniciado por Leonidas"* → "Voltar a ser
  eu" → de volta como OG, faixa some.

`document.documentElement.scrollWidth <= window.innerWidth` em **todas** as rotas e nas duas
larguras. **Zero erro de console** na última passada completa.

### Nota sobre 1.4 — a DEC vence o `tasks.md`

A tarefa 1.4 diz "**`username` não é portado**". A **DEC-45**, posterior, decidiu o
contrário: `username` é portado como identificador alternativo, coluna nullable com
índice único parcial. Foi a DEC-45 que valeu. A tarefa fica marcada com esta ressalva.

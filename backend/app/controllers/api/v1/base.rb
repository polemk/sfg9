# frozen_string_literal: true

module Api
  module V1
    class Base < Grape::API
      format :json
      version 'v1', using: :path
      prefix :api

      helpers Api::V1::ControllerHelpers

      before do
        # Generalização do antigo `restrict_visitor_access!` (DEC-41 removeu o
        # tipo `visitor`): o predicado agora é a concessão ativa de
        # `user_is_readonly`, a única das 17 abilities do legado que sobrevive
        # (DEC-18.6). O gate continua rodando em todo `/api/v1/*`.
        require_not_readonly!
      end

      namespace :users do
        mount Api::V1::Users
      end

      mount Api::V1::Memberships
      mount Api::V1::UserTypes
      mount Api::V1::AuditTrail

      # S2 — seletor de projeto (BE-412) e mensagens administrativas (Grupo B).
      mount Api::V1::CurrentProject
      mount Api::V1::AdminMessages
      mount Api::V1::Observers

      mount Api::V1::Chat
      mount Api::V1::ChatFlows
      mount Api::V1::FlowExecutions
      mount Api::V1::Credentials

      namespace :uploads do
        mount Api::V1::Uploads
      end

      # S13 / OPS-491, OPS-492 — motor unico de anexos (sub-bloco B, antecipado
      # pela DEC-63). Unico caminho de leitura de binario do Safegold: autoriza
      # primeiro, assina depois. `Api::V1::Uploads` continua montado porque e da
      # base e outros sistemas dependem dele (Principio 6b / F-09) — o Safegold
      # nao o usa.
      mount Api::V1::Attachments

      mount Api::V1::Countries

      # S13 / OPS-480, BE-457 — autopreenchimento por CNPJ (DEC-46). Recurso proprio
      # porque tres formularios diferentes consomem a mesma integracao.
      mount Api::V1::CnpjLookup

      # S3 — os cinco CATÁLOGOS GLOBAIS mais as UFs (OPS-057).
      #
      # Montados aqui dentro, herdam o `before { require_not_readonly! }` acima e
      # o gate de credencial do `Api::Root`. É o que faz "sem credencial → 401"
      # ser o comportamento PADRÃO destes endpoints — e é o defeito literal do
      # legado que isso fecha: `ProjectGuaranteeTypesController` declarava
      # `requires_current_user? == false` e respondia para anônimo (D-23).
      #
      # **Nenhum destes seis chama `current_project!`**: catálogo global não
      # recebe escopo de projeto (contrato C1, regra 4 de `§0.6`).
      mount Api::V1::Carriers
      mount Api::V1::CarrierGroups
      mount Api::V1::Segments
      mount Api::V1::SubSegments
      mount Api::V1::ProjectGuaranteeTypes
      mount Api::V1::BrStates

      # S4 — **os recursos ESCOPADOS POR PROJETO** (contrato C1).
      #
      # Regra oposta à dos cinco catálogos acima, e oposta de propósito: cada
      # ação destes cinco declara `project = current_project!` numa linha
      # visível, e o `project_id` que vier no CORPO é sempre ignorado (ele nem é
      # declarado nos `params do`). É a ausência dessa declaração que fecha a
      # família D-01 / D-16 / D-29 / D-76 / D-100 — no legado, sempre que
      # chegava um id por parâmetro, o filtro de projeto era descartado.
      #
      # `Api::V1::Projects` é a exceção que confirma a regra: ele responde
      # "quais projetos existem para este usuário" (`Project.visible_to`), que é
      # outra pergunta — escopá-lo pelo projeto corrente seria circular.
      mount Api::V1::Projects
      mount Api::V1::Companies
      mount Api::V1::Providers
      mount Api::V1::ProjectGuarantees
      mount Api::V1::ProjectCarrierConnections

      # S11 — **disponibilidades** (DEC-15.1: as telas estão vivas em produção).
      #
      # `AvailabilityTemplates` é o **catálogo global** e, como os seis de cima,
      # **não** chama `current_project!` — regra 4 do C1. Os outros três são
      # escopados por projeto e declaram `current_project!` em toda ação.
      #
      # `Availability` monta também `/projects/:id/availability`, a rota do
      # **D-01**: no legado ela herdava de `ApplicationController` e respondia
      # **sem sessão nenhuma**, a qualquer projeto por id. Montada aqui, herda a
      # autenticação global — "sem credencial → 401" passa a ser o padrão.
      mount Api::V1::AvailabilityTemplates
      mount Api::V1::ProjectAvailabilities
      mount Api::V1::AvailabilityEntries
      mount Api::V1::AvailabilityPanel

      # S5 — **limites de risco e o motor de exposição**.
      #
      # Duas regras opostas, as duas de propósito:
      #
      #  - `RiskControls` é **escopado por projeto** (C1): toda ação declara
      #    `project = current_project!` numa linha visível, e o `project_id` do
      #    corpo nem é declarado nos `params do`;
      #  - `RiskOperationTypes` e `RiskMovementTypes` são **catálogos GLOBAIS**
      #    (C1, regra 4) e NÃO chamam `current_project!` — o Colaborador precisa
      #    lê-los para que o select do formulário de limite suba populado
      #    (DEC-18.4), mesmo sem ver a tela de administração.
      mount Api::V1::RiskControls
      mount Api::V1::RiskOperationTypes
      mount Api::V1::RiskMovementTypes

      # S7 — **operações de risco**, com movimentos, prorrogações e renovação
      # ANINHADOS no mesmo recurso. Não há `mount` separado para movimento nem
      # para prorrogação de propósito: os dois só existem dentro de uma operação,
      # e é o aninhamento que torna impossível alcançá-los sem passar pelo
      # `current_project!` da operação — que é exatamente a IDOR do legado
      # (`risk_movements#search` aceitava qualquer `risk_operation_id`, sem
      # escopo nenhum).
      mount Api::V1::RiskOperations

      # S6 — **recebíveis, cobranças e os três catálogos do borderô**.
      #
      # As mesmas duas regras opostas, e vale reler por quê:
      #
      #  - `Receivables` e `Charges` são **escopados por projeto** (C1): toda
      #    ação declara `project = current_project!` numa linha visível, e
      #    `project_id` nem é declarado nos `params do`. É a correção literal da
      #    família D-01/D-16/D-29/D-76/D-100 — no legado, id por parâmetro
      #    descartava o filtro de projeto;
      #  - `Wallets`, `ReceivableKinds` e `MovementKinds` são **catálogos
      #    GLOBAIS** (C1, regra 4) e NÃO chamam `current_project!`. Uma carteira
      #    "do projeto A" sumiria do projeto B e quebraria os borderôs que já
      #    apontam para ela. O Colaborador lê os três para que os selects do
      #    formulário de borderô subam populados (DEC-18.4).
      #
      # `Receivables` monta também `/receivable_help_texts` (OPS-154).
      mount Api::V1::Receivables
      mount Api::V1::Charges
      mount Api::V1::Wallets
      mount Api::V1::ReceivableKinds
      mount Api::V1::MovementKinds
      # **DONA: S8** — a S6 montava só a LEITURA, por dependência dura: o
      # `resource_source_id` do borderô é obrigatório e sem este `GET` o
      # formulário não pode ser enviado. A **S8 fechou a superfície de
      # escrita** (`BE-725`…`BE-729`). Ver `api/v1/resource_sources.rb`.
      mount Api::V1::ResourceSources

      # S8 — **operações estruturadas, tipos e remunerações**.
      #
      # As mesmas duas regras opostas de sempre, e aqui elas se cruzam num só
      # bloco, o que é justamente o motivo de estarem escritas:
      #
      #  - `StructuredOperations` e `Remunerations` são **escopados por
      #    projeto** (C1): toda ação declara `project = current_project!` numa
      #    linha visível. É a correção de duas IDORs medidas — o
      #    `structured_operation_id` que descartava o escopo inteiro (BE-280) e
      #    o `project_id` de campo hidden da remuneração (BE-301);
      #  - `StructuredOperationTypes` é **catálogo GLOBAL** (C1, regra 4) e NÃO
      #    chama `current_project!`. Um tipo vale para todos os projetos, e
      #    escondê-lo por projeto quebraria a remuneração que já aponta para ele.
      #
      # **FE-309, a correção de segurança da unidade:** os controllers dedicados
      # do legado herdam `requires_current_user? == false` — `search`, `create`,
      # `update` e `destroy` **não exigem login pelo `before_action`**.
      # Funcionavam só porque `current_user` precisava existir para
      # `current_user.default_project_id` não quebrar, o que é acidente e não
      # autorização. Os três abaixo exigem JWT válido **e** passam pela
      # `Authorization::Matrix`, como todo o resto do ai9.
      mount Api::V1::StructuredOperations
      mount Api::V1::StructuredOperationTypes
      mount Api::V1::Remunerations

      # S10 — **indicadores**. Duas regras opostas no mesmo módulo, e as duas de
      # propósito:
      #
      #  - `Indicators` é **catálogo GLOBAL** (`project_id IS NULL`) e NÃO chama
      #    `current_project!` para ler — o Colaborador lê (DEC-18.4). O projeto
      #    só entra quando a operação é sobre um indicador ESPECÍFICO, e vem do
      #    `current_project!`, nunca do corpo;
      #  - `IndicatorEntries` e `IndicatorConnections` são **escopados por
      #    projeto** (C1), como os cinco da S4 acima.
      #
      # Os três fecham o **BE-717**: no legado nenhum dos controllers de
      # indicador tem um único `before_action` de permissão — toda a autorização
      # era de view, e qualquer autenticado podia gravar direto.
      mount Api::V1::Indicators
      mount Api::V1::IndicatorConnections
      mount Api::V1::IndicatorEntries

      # S9 — **renegociações**. Os quatro são escopados por projeto (C1) e
      # declaram `current_project!` em toda ação; os três de baixo são
      # **aninhados** em `/renegotiations/:renegotiation_id/…`, para que o escopo
      # pai fique visível na própria URL. No legado as rotas eram planas e a
      # renegociação vinha por parâmetro — foi assim que `renegotiation_id` virou
      # um seletor global que atravessava projeto (D-01 / D-16 / D-29 / D-76 /
      # D-100).
      #
      # ⚠ `RenegotiationPayments` é **backend sem tela**, por DEC-53: a aba
      # PAGAMENTOS não é portada (no legado ela está comentada). Justamente por
      # isso as rotas passam pela matriz e pelo `current_project!` como qualquer
      # outra — backend sem tela sem dono de autorização foi como o P-022 nasceu.
      mount Api::V1::Renegotiations
      mount Api::V1::RenegotiationInstallments
      mount Api::V1::RenegotiationPayments
      mount Api::V1::RenegotiationAttachments

      # DEC-61: entrega a chave do Google Maps ao navegador em runtime, para que ela
      # possa viver encriptada no `Credential` em vez de assada no bundle do Vite.
      # Exige sessão pelo gate de `Api::Root` — não está na allowlist pública.
      mount Api::V1::RuntimeConfig

      mount Api::V1::Downloads

      # S15 / NEW-001 + NEW-002 — o painel da tela inicial e o volume por
      # portador. **Feature nova (DEC-21), não paridade**: compõe serviços de
      # domínio de S5/S6/S9 e não calcula nada por conta própria (contrato C2).
      mount Api::V1::Dashboard

      # S12 — contratos, ajuda e FAQ.
      #
      # `Contracts` monta `/contracts` **e** `/me/terms`: as duas rotas de
      # aceite, que são as isentas de `READONLY_EXEMPT_PATHS`. `ContractVersions`
      # é o recurso separado da DEC-38, gateado por OG + Admin.
      mount Api::V1::Contracts
      mount Api::V1::ContractVersions
      mount Api::V1::Help

      namespace :auth do
        mount Api::Auth::V1::Registration
        mount Api::Auth::V1::Sessions
      end

      namespace :permissions do
        mount Api::V1::Permissions
      end

      namespace :public do
        mount Api::V1::Public::Chat
        # S12 / BE-330 — leitura de contrato SEM sessão. A allowlist de
        # `Api::Root` libera esta rota por CAMINHO, nunca por cabeçalho.
        mount Api::V1::Public::Contracts
      end

      # Tratamento de erros específico, se necessário
      rescue_from Grape::Exceptions::ValidationErrors do |e|
        error!({ error: e.message, details: e.errors }, 400)
      end

      # **S7 / B-09** — catálogo de referência incompleto é erro de NEGÓCIO, não 500.
      #
      # `RiskMovementType.release` / `.transfer_out` / `.transfer_in` levantam
      # {RiskMovementType::MissingFunctionalType} quando a chave de integração
      # não existe. Isso acontece **antes** de qualquer gravação (é o ponto da
      # B-09: no legado era `NoMethodError` em `nil.id`, depois do INSERT), e a
      # mensagem já nomeia a chave e diz o que rodar.
      #
      # Fica aqui, e não só no endpoint de risco, porque o `after_create` de
      # `RiskOperation` dispara também **dentro do borderô** (S6): sem esta
      # linha, um borderô num ambiente com o catálogo faltando responde 500 em
      # vez de dizer o que falta. Foi exatamente o que o
      # `spec/requests/api/v1/receivables_spec.rb:440` mostrou.
      rescue_from RiskMovementType::MissingFunctionalType do |e|
        error!({ error: 'unprocessable_entity', message: e.message }, 422)
      end

      # **S2 / tarefa 2.8 — o verbo errado numa rota de detalhe respondia 500.**
      #
      # `Grape::Exceptions::Base` já CARREGA o status certo (o `MethodNotAllowed`
      # é 405, o `InvalidVersionHeader` é 406, e por aí). O handler herdado da
      # base ai9 engolia todos e devolvia **500** — o `unless` acima só decidia
      # se montava uma variável local `env` que nunca era usada, e o
      # `error!(error_backtrace)` no fim rodava para TODA exceção, sem status.
      #
      # Medido no servidor de dev, com sessão de Admin:
      # `GET /api/v1/project_carrier_connections/<uuid>` (a conexão só expõe
      # `DELETE :id`) respondia **500** onde o certo é **405**, com o cabeçalho
      # `Allow: OPTIONS, DELETE` já correto ao lado. É literalmente o defeito que
      # a 2.8 manda eliminar — "500 de verdade" numa URL de detalhe.
      #
      # **O corpo também vazava o backtrace inteiro**, em qualquer ambiente: 9,5 KB
      # de caminhos de gem, versões e caminho absoluto do código na resposta HTTP.
      # Isso é EXCECAO-2 do DEC-30 (segurança), onde replicar não se aplica: o
      # backtrace vai para o log, que é onde se depura, e o cliente recebe o
      # `X-Request-Id` para casar uma coisa com a outra.
      #
      # Achado da base ai9 (o nome "POLEMK" denuncia a origem) — registrado em
      # `.migration-ai9/upstream-flags.md`. Alterado aqui por DEC-50: a `sfg9` é
      # produto próprio, e a regra da 2.8 exige a mudança.
      rescue_from Grape::Exceptions::Base do |e|
        error!({ error: e.class.name.demodulize.underscore, message: e.message }, e.status || 500)
      end

      rescue_from :all do |e|
        # O backtrace fica no LOG. Nunca no corpo.
        Rails.logger.error("[api/v1] #{e.class}: #{e.message}\n#{Array(e.backtrace).join("\n")}")

        error!({
                 error: 'internal_server_error',
                 message: 'Erro interno. Se persistir, informe o identificador da requisição.',
                 request_id: env['action_dispatch.request_id']
               }, 500)
      end
    end
  end
end

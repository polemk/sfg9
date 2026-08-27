# frozen_string_literal: true

require 'rails_helper'

# S6 — **os três catálogos GLOBAIS do borderô**, provados pela API:
# `/api/v1/wallets`, `/api/v1/receivable_kinds` e `/api/v1/movement_kinds`.
#
# Fecha `BE-185`, `BE-186`, `BE-446`, `BE-447`, `BE-448` e a `Q-B12`.
#
# O que este arquivo prova é uma coisa só, vista de cinco ângulos: **catálogo
# global não é recurso de projeto**. É a regra 4 do contrato C1, e ela é o
# OPOSTO da regra que vale para borderô, cobrança e limite de risco. As duas
# convivem no mesmo código, então a única forma de a segunda não contaminar a
# primeira é afirmá-la em teste — do contrário, o próximo a mexer aqui
# acrescenta `current_project!` por analogia e some com a carteira "Fomento" de
# 28 mil borderôs.
RSpec.describe 'API V1 Catálogos do borderô', type: :request do
  let(:og) { create(:user, :og) }
  let(:project) { create_project_with_owner(og) }
  let(:headers) { auth_headers(og, project: project) }

  # ====================================================================
  # C1, regra 4 — o catálogo é GLOBAL
  # ====================================================================
  describe 'C1 regra 4 — os três catálogos NÃO são escopados por projeto' do
    let(:outro_og) { create(:user, :og) }
    let(:outro_projeto) { create_project_with_owner(outro_og) }

    let!(:wallet) { create(:wallet, title: 'Fomento') }
    let!(:kind) { create(:receivable_kind, title: 'Duplicata') }
    let!(:movement) { create(:movement_kind, title: 'TAC') }

    {
      'wallets' => 'Fomento',
      'receivable_kinds' => 'Duplicata',
      'movement_kinds' => 'TAC'
    }.each do |rota, titulo|
      it "um usuário de OUTRO projeto lê o MESMO #{rota}" do
        # O registro foi cadastrado sem projeto nenhum e tem de aparecer para
        # os dois. Se algum dia este exemplo falhar, o borderô de 2022 que
        # aponta para a carteira "Fomento" passa a exibir campo vazio no
        # projeto que não a "cadastrou" — e não há como recuperar o vínculo
        # pela tela.
        get "/api/v1/#{rota}", headers: headers
        meus = response.parsed_body.map { |r| r['title'] }

        get "/api/v1/#{rota}", headers: auth_headers(outro_og, project: outro_projeto)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.map { |r| r['title'] }).to eq(meus)
        expect(meus).to include(titulo)
      end

      it "GET #{rota}/:id responde 200 para quem está em outro projeto" do
        # Detalhe também é global: o painel lateral de edição abre a partir de
        # qualquer projeto. Aqui um 404 seria a assinatura de escopo indevido.
        alvo = { 'wallets' => wallet, 'receivable_kinds' => kind, 'movement_kinds' => movement }.fetch(rota)
        get "/api/v1/#{rota}/#{alvo.id}", headers: auth_headers(outro_og, project: outro_projeto)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['title']).to eq(titulo)
      end

      it "#{rota} responde SEM `X-Project-Id` — o endpoint não chama `current_project!`" do
        # Um usuário recém-criado, sem projeto escolhido, precisa que os
        # dropdowns carreguem. Se o endpoint pedisse projeto, a resposta aqui
        # seria 404/409 e a tela de criação do primeiro borderô nasceria vazia.
        get "/api/v1/#{rota}", headers: auth_headers(og)
        expect(response).to have_http_status(:ok)
      end
    end

    it 'nenhum dos três models responde `project_scoped?`' do
      # `ProjectScoped.project_scoped?` é o marcador de leitura do C1. Ele
      # existir nestes três seria o sintoma de que alguém incluiu o concern
      # errado — o teste custa uma linha e pega a mudança no dia em que ela
      # acontece, não seis meses depois no relatório do cliente.
      [Wallet, ReceivableKind, MovementKind].each do |model|
        expect(model).not_to respond_to(:project_scoped?), "#{model} não pode ser escopado por projeto (C1 regra 4)"
        expect(model.global_catalog?).to be(true)
      end
    end

    it 'nenhum dos três tem `default_scope`' do
      # `default_scope` vaza para `unscoped`, quebra `joins` em silêncio e
      # contamina job e seed. O escopo, quando existe, é aplicado no endpoint.
      [Wallet, ReceivableKind, MovementKind].each do |model|
        expect(model.default_scopes).to be_empty, "#{model} não pode ter default_scope"
      end
    end

    it 'nenhuma das três tabelas tem coluna `project_id`' do
      # A prova no nível do esquema. Sem a coluna, nem um `where` distraído
      # consegue escopar.
      [Wallet, ReceivableKind, MovementKind].each do |model|
        expect(model.column_names).not_to include('project_id')
      end
    end
  end

  # ====================================================================
  # BE-446 — a chave de integração
  # ====================================================================
  describe 'BE-446 — `integration_key` derivada na criação e CONGELADA na edição' do
    it 'deriva a chave do título quando ela não vem no corpo' do
      # `../sfg/app/models/movement_kind.rb:5-7` e `wallet.rb:4-6` fazem o
      # mesmo `before_validation … on: [:create]`. A forma da chave é a mesma
      # (transliteração + minúsculas + sublinhado) porque a chave dos registros
      # migrados não pode mudar de forma — é chave de INTEGRAÇÃO.
      post '/api/v1/wallets', params: { title: 'Carteira de Fomento' }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['integration_key']).to eq('carteira_de_fomento')
    end

    it 'renomear o título depois NÃO muda a chave' do
      # É aqui que o legado divergia: o `before_validation` era `on: [:create]`,
      # mas `integration_key` continuava no `permit` do controller e a tela a
      # reescrevia a cada submit. Resultado: título e chave divergiam na
      # PRIMEIRA edição, sem ninguém pedir. Aqui a chave nem é atributo
      # gravável no `update` (`CatalogService#writable_attributes` só a aceita
      # na criação, via `assign` do `create`).
      post '/api/v1/wallets', params: { title: 'Carteira de Fomento' }, headers: headers, as: :json
      id = response.parsed_body['id']

      put "/api/v1/wallets/#{id}", params: { title: 'Carteira de Antecipação' }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['title']).to eq('Carteira de Antecipação')
      expect(response.parsed_body['integration_key']).to eq('carteira_de_fomento')
    end

    it 'a chave explícita na criação é respeitada — quem integra escolhe a sua' do
      post '/api/v1/receivable_kinds', params: { title: 'Duplicata Mercantil', integration_key: 'DUP-01' },
                                       headers: headers, as: :json

      expect(response.parsed_body['integration_key']).to eq('DUP-01')
    end

    it 'a mesma regra vale nos três catálogos' do
      %w[wallets receivable_kinds movement_kinds].each_with_index do |rota, i|
        post "/api/v1/#{rota}", params: { title: "Título Composto #{i}" }, headers: headers, as: :json
        expect(response.parsed_body['integration_key']).to eq("titulo_composto_#{i}")

        put "/api/v1/#{rota}/#{response.parsed_body['id']}", params: { title: "Outro Nome #{i}" },
                                                             headers: headers, as: :json
        expect(response.parsed_body['integration_key']).to eq("titulo_composto_#{i}")
      end
    end
  end

  # ====================================================================
  # BE-447 — exclusividade dos classificadores
  # ====================================================================
  describe 'BE-447 — no máximo UM classificador de taxa' do
    # Fonte: `../sfg/app/models/movement_kind.rb:13-18`. A validação existe no
    # legado; o que não existe é a mensagem legível — lá o `errors.add` usa a
    # frase **"Múltiplos tipos"** como se fosse nome de atributo, e o usuário
    # lê "Múltiplos tipos Pode ter apenas um dos tipos definidos".
    #
    # Há ainda um segundo defeito no legado, invisível na leitura: as quatro
    # colunas eram `integer` NULLABLE e `[nil, 1, nil, nil].sum` levanta
    # `TypeError`. Aqui são `boolean NOT NULL DEFAULT false` — o `nil` deixou
    # de existir.
    [
      %i[is_advalorem is_desagio],
      %i[is_advalorem is_iof],
      %i[is_desagio is_iof],
      %i[is_iof is_liquidation],
      %i[is_advalorem is_liquidation]
    ].each do |par|
      it "recusa com 422 e mensagem pt-BR: #{par.join(' + ')}" do
        corpo = { title: "Tarifa #{par.join('_')}" }.merge(par.index_with { true })
        post '/api/v1/movement_kinds', params: corpo, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        mensagem = response.parsed_body['message']
        expect(mensagem).to include('no máximo um classificador')
        expect(mensagem).to include('AdValorem', 'Deságio', 'IOF', 'Liquidação')
        # O texto cru do legado não pode reaparecer.
        expect(mensagem).not_to include('Múltiplos tipos')
        expect(MovementKind.where(title: corpo[:title])).not_to exist
      end
    end

    it 'os quatro juntos também recusam' do
      post '/api/v1/movement_kinds',
           params: { title: 'Tudo ao mesmo tempo', is_advalorem: true, is_desagio: true,
                     is_iof: true, is_liquidation: true },
           headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    MovementKind::TAX_CLASSIFIERS.each do |flag|
      it "aceita UM classificador: #{flag}" do
        post '/api/v1/movement_kinds', params: { title: "Tarifa só #{flag}", flag => true },
                                       headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(response.parsed_body['tax_classifier']).to eq(flag.to_s)
      end
    end

    it 'aceita NENHUM classificador — é o caso de "Outras Despesas" em produção' do
      post '/api/v1/movement_kinds', params: { title: 'Outras Despesas' }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['tax_classifier']).to be_nil
    end

    it 'a EDIÇÃO que marcaria o segundo classificador também recusa' do
      # O caminho que o legado deixava aberto na prática: cadastrar com um e
      # marcar o outro depois.
      movimento = create(:movement_kind, :advalorem)

      put "/api/v1/movement_kinds/#{movimento.id}", params: { is_desagio: true }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(movimento.reload.is_desagio).to be(false)
    end

    it 'o `check_constraint` do banco recusa mesmo BURLANDO o model' do
      # A validação de model não vê a corrida entre duas abas nem o caminho que
      # não passa por ela (rake, console, conversor de ETL). O
      # `movement_kinds_single_tax_kind_check` é a segunda camada, e
      # `update_columns` é justamente o caminho que pula validação e callback.
      movimento = create(:movement_kind, :advalorem)

      # O `requires_new: true` abre um SAVEPOINT: sem ele o `PG` aborta a
      # transação do exemplo inteiro e o `reload` seguinte falha com
      # `InFailedSqlTransaction` — o que esconderia o que se quer afirmar.
      expect {
        ActiveRecord::Base.transaction(requires_new: true) do
          movimento.update_columns(is_advalorem: true, is_desagio: true)
        end
      }.to raise_error(ActiveRecord::StatementInvalid, /movement_kinds_single_tax_kind_check/)

      expect(movimento.reload.is_desagio).to be(false)
      expect(movimento.is_advalorem).to be(true)
    end
  end

  # ====================================================================
  # BE-448 / D-24 — exclusão bloqueada NOMEIA o vínculo
  # ====================================================================
  describe 'BE-448 / D-24 — exclusão bloqueada por vínculo' do
    let(:company) { create(:company, project: project) }
    let(:carrier) { create(:carrier) }

    it 'movement_kind COM tarifa vinculada responde 422 nomeando "tarifa(s) de borderô"' do
      # `../sfg/app/models/movement_kind.rb:2-3` declarava
      # `dependent: :restrict_with_error` em duas associações — e o controller
      # do legado transformava o `destroy` recusado em **500**, ou pior,
      # respondia `:ok` (D-24) e a tela dizia "removido".
      movimento = create(:movement_kind)
      create(:receivable_tax, movement_kind: movimento,
                              receivable_entry: create(:receivable_entry, project: project,
                                                                          company: company, carrier: carrier))

      expect { delete "/api/v1/movement_kinds/#{movimento.id}", headers: headers }
        .not_to(change { MovementKind.count })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('tarifa(s) de borderô')
      expect(response.parsed_body['message']).to include('1 ')
      expect(MovementKind.exists?(movimento.id)).to be(true)
    end

    it 'movement_kind SEM vínculo exclui normalmente' do
      movimento = create(:movement_kind)

      delete "/api/v1/movement_kinds/#{movimento.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['deleted']).to be(true)
      expect(MovementKind.exists?(movimento.id)).to be(false)
    end

    it 'wallet COM borderô vinculado responde 422 nomeando "borderô(s)"' do
      carteira = create(:wallet)
      create(:receivable_entry, project: project, company: company, carrier: carrier, wallet: carteira)

      delete "/api/v1/wallets/#{carteira.id}", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('borderô(s)')
      expect(Wallet.exists?(carteira.id)).to be(true)
    end

    it 'receivable_kind COM borderô vinculado responde 422 nomeando "borderô(s)"' do
      tipo = create(:receivable_kind)
      create(:receivable_entry, project: project, company: company, carrier: carrier, receivable_kind: tipo)

      delete "/api/v1/receivable_kinds/#{tipo.id}", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('borderô(s)')
      expect(ReceivableKind.exists?(tipo.id)).to be(true)
    end

    it 'o vínculo bloqueia mesmo quando o borderô é de OUTRO projeto' do
      # O catálogo é global: o dependente que bloqueia também é procurado em
      # toda a base, não no projeto corrente. Contar só o projeto do ator faria
      # a exclusão "passar" na validação e bater na FK do Postgres — 500 em vez
      # de 422, e num caminho que só aparece com dois tenants ativos.
      outro_projeto = create_project_with_owner(create(:user, :og))
      carteira = create(:wallet)
      create(:receivable_entry, project: outro_projeto,
                                company: create(:company, project: outro_projeto), wallet: carteira)

      delete "/api/v1/wallets/#{carteira.id}", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Wallet.exists?(carteira.id)).to be(true)
    end

    it 'a listagem publica a contagem que EXPLICA o 422' do
      # O número na coluna da tela e o número da frase de bloqueio saem da
      # mesma consulta (`CatalogService#usage_counts`). Duas fontes dariam
      # "0 borderôs" na tela e "não é possível excluir" no clique.
      carteira = create(:wallet)
      2.times { create(:receivable_entry, project: project, company: company, carrier: carrier, wallet: carteira) }

      get '/api/v1/wallets', headers: headers
      linha = response.parsed_body.find { |r| r['id'] == carteira.id }
      expect(linha['receivable_entries_count']).to eq(2)
    end
  end

  # ====================================================================
  # Q-B12 — `is_active` NÃO filtra por padrão
  # ====================================================================
  describe 'Q-B12 — `is_active` não filtra a listagem' do
    # No legado a coluna existe, tem tela e **nenhuma consulta a lê**. Passar a
    # filtrar por padrão faria a carteira "desativada" sumir do select do
    # borderô — e quebraria o formulário de quem lança sobre ela, além de
    # deixar 28 mil registros históricos apontando para um id invisível.
    %w[wallets receivable_kinds movement_kinds].each do |rota|
      factory = { 'wallets' => :wallet, 'receivable_kinds' => :receivable_kind,
                  'movement_kinds' => :movement_kind }.fetch(rota)

      it "#{rota}: registro DESATIVADO continua na listagem sem `active=true`" do
        desativado = create(factory, is_active: false)
        create(factory)

        get "/api/v1/#{rota}", headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.map { |r| r['id'] }).to include(desativado.id)
        expect(response.parsed_body.size).to eq(2)
      end

      it "#{rota}: `active=true` é filtro EXPLÍCITO e aí sim filtra" do
        desativado = create(factory, is_active: false)
        ativo = create(factory)

        get "/api/v1/#{rota}", params: { active: true }, headers: headers

        ids = response.parsed_body.map { |r| r['id'] }
        expect(ids).to eq([ativo.id])
        expect(ids).not_to include(desativado.id)
      end
    end
  end

  # ====================================================================
  # Ordenação, filtro e paginação
  # ====================================================================
  describe 'ordenação' do
    before do
      create(:wallet, title: 'Zeta')
      create(:wallet, title: 'Alfa')
      create(:wallet, title: 'Meio')
    end

    it 'chave desconhecida é IGNORADA — 200, não 500' do
      # `../sfg/app/models/wallet.rb:25` fazia
      # `get_ordering_key(key) + " " + get_ordering_style(style)`, e
      # `get_ordering_key` cai num `case` sem `else`: chave fora da lista
      # devolve `nil` e `nil + " "` levanta `NoMethodError`. Bastava digitar
      # `?ordering_keys[]=x` na barra de endereço para derrubar o request.
      get '/api/v1/wallets', params: { ordering_keys: ['drop table'], ordering_style: ['up'] }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.size).to eq(3)
    end

    it 'estilo desconhecido cai no ascendente, sem erro' do
      # `get_ordering_style` do legado também não tem `else`.
      get '/api/v1/wallets', params: { ordering_keys: ['title'], ordering_style: ['sideways'] }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.map { |r| r['title'] }).to eq(%w[Alfa Meio Zeta])
    end

    it 'ordena pelas duas chaves do legado (`title` e `key`)' do
      get '/api/v1/wallets', params: { ordering_keys: ['title'], ordering_style: ['down'] }, headers: headers
      expect(response.parsed_body.map { |r| r['title'] }).to eq(%w[Zeta Meio Alfa])

      get '/api/v1/wallets', params: { ordering_keys: ['key'], ordering_style: ['up'] }, headers: headers
      chaves = response.parsed_body.map { |r| r['integration_key'] }
      expect(chaves).to eq(chaves.sort)
    end
  end

  describe '`for_operation` em movement_kinds' do
    it 'devolve SÓ os `is_operation`' do
      # É o único dos flags de exibição do legado que tem leitor
      # (`receivables/new/_body.html.erb` monta a lista de tarifas com ele).
      # Os outros dois (`is_title`, `is_liquidation`) foram portados sem
      # consumidor — D-74 / Q-B13.
      da_lista = create(:movement_kind, is_operation: true)
      create(:movement_kind, is_operation: false)

      get '/api/v1/movement_kinds', params: { for_operation: true }, headers: headers

      expect(response.parsed_body.map { |r| r['id'] }).to eq([da_lista.id])
    end

    it 'sem o filtro, os dois aparecem' do
      create(:movement_kind, is_operation: true)
      create(:movement_kind, is_operation: false)

      get '/api/v1/movement_kinds', headers: headers
      expect(response.parsed_body.size).to eq(2)
    end
  end

  describe 'paginação (DEC-62)' do
    before { 45.times { |i| create(:wallet, title: format('Carteira %02d', i)) } }

    it 'emite os cabeçalhos que o `PaginationPill` lê' do
      get '/api/v1/wallets', params: { page: 2, per_page: 20 }, headers: headers

      expect(response.parsed_body.size).to eq(20)
      expect(response.headers['X-Total-Count']).to eq('45')
      expect(response.headers['X-Page']).to eq('2')
      expect(response.headers['X-Per-Page']).to eq('20')
      expect(response.headers['X-Total-Pages']).to eq('3')
    end

    it 'a ÚLTIMA página traz o resto' do
      get '/api/v1/wallets', params: { page: 3, per_page: 20 }, headers: headers
      expect(response.parsed_body.size).to eq(5)
    end

    it 'o total do cabeçalho é o da CONSULTA, não o da página' do
      # No legado `limit`/`offset` eram lidos e descartados (D-20): a UI de
      # paginação era decorativa e a última página ia para o lugar errado.
      get '/api/v1/wallets', params: { q: 'Carteira 0', per_page: 5 }, headers: headers
      expect(response.parsed_body.size).to eq(5)
      expect(response.headers['X-Total-Count']).to eq('10')
    end
  end

  # ====================================================================
  # Autorização NO SERVIDOR — DEC-18.4
  # ====================================================================
  describe 'autorização (DEC-18.4)' do
    let(:colaborador) { create(:user, :colaborador) }

    before { Membership.create!(project: project, user: colaborador, role: 'participante') }

    %w[wallets receivable_kinds movement_kinds].each do |rota|
      it "Colaborador LÊ #{rota}" do
        # DEC-18.4, a regra em uma frase: **o menu esconde a tela de
        # administração do catálogo, não o dado do catálogo.** Sem isso todo
        # dropdown do Colaborador quebra no dia 1 — inclusive o do borderô, que
        # ele tem `CRUD` para lançar.
        get "/api/v1/#{rota}", headers: auth_headers(colaborador, project: project)
        expect(response).to have_http_status(:ok)
      end

      it "Colaborador NÃO cria em #{rota}" do
        # A matriz dá `R` ao Colaborador nos três. Esconder o botão nunca foi
        # autorização: no legado o único gate era de view (D-23) e a requisição
        # fora da tela fazia tudo (D-34).
        expect {
          post "/api/v1/#{rota}", params: { title: 'Criado por quem não pode' },
                                  headers: auth_headers(colaborador, project: project), as: :json
        }.not_to(change { rota.classify.constantize.count })

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body['code']).to eq('ROLE_REQUIRED')
      end

      it "Colaborador NÃO edita nem exclui em #{rota}" do
        registro = create({ 'wallets' => :wallet, 'receivable_kinds' => :receivable_kind,
                            'movement_kinds' => :movement_kind }.fetch(rota), title: 'Intocável')
        cabecalhos = auth_headers(colaborador, project: project)

        put "/api/v1/#{rota}/#{registro.id}", params: { title: 'Renomeado' }, headers: cabecalhos, as: :json
        expect(response).to have_http_status(:forbidden)

        delete "/api/v1/#{rota}/#{registro.id}", headers: cabecalhos
        expect(response).to have_http_status(:forbidden)

        expect(registro.reload.title).to eq('Intocável')
      end

      it "sem credencial, #{rota} responde 401" do
        get "/api/v1/#{rota}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    it 'somente-leitura não escreve, mesmo sendo OG' do
      # `user_is_readonly` é a única das 17 abilities do legado que sobrevive
      # (DEC-18.6), promovida de flag de view a checagem de servidor.
      permissao = Permission.find_or_create_by!(key: 'user_is_readonly') { |p| p.title = 'Somente leitura' }
      UserPermission.create!(user: og, permission: permissao, granted_at: Time.current, source: 'manual')

      post '/api/v1/wallets', params: { title: 'Não deve nascer' }, headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['code']).to eq('READONLY_RESTRICTED')
      expect(Wallet.count).to eq(0)
    end
  end

  # ====================================================================
  # D-12 — a corrida entre duas abas
  # ====================================================================
  describe 'D-12 — título único fecha a corrida entre duas abas' do
    it 'título repetido responde 422, não 500' do
      # O legado tinha `validates :title, uniqueness: true` e **nenhum índice**
      # (`../sfg/app/models/wallet.rb:3`): duas abas gravavam duas carteiras
      # com o mesmo nome. Aqui há índice único, e o `RecordNotUnique` que ele
      # levanta vira 422 com texto de humano (`CatalogService#save_safely`).
      create(:wallet, title: 'Fomento')

      post '/api/v1/wallets', params: { title: 'Fomento' }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Wallet.where(title: 'Fomento').count).to eq(1)
    end

    it 'id malformado responde 404, não o `PG::InvalidTextRepresentation`' do
      get '/api/v1/wallets/nao-e-uuid', headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end

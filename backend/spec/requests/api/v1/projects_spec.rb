# frozen_string_literal: true

require 'rails_helper'

# S4 / 3.x, 7.1.1, 7.1.9, 7.4.1..7.4.4, 7.4.6 — **o CRUD do projeto**.
RSpec.describe 'API V1 Projects', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:gerente) { create(:user, user_type: UserType.gerente) }
  let(:outro) { create(:user, user_type: UserType.gerente) }

  let!(:projeto_a) { create_project_with_owner(gerente, slug: 'proj-a', name: 'Alfa Incorporadora') }
  let!(:projeto_b) { create_project_with_owner(outro, slug: 'proj-b', name: 'Beta Construtora') }

  describe 'GET /api/v1/projects' do
    it 'traz só os projetos em que o usuário participa' do
      get '/api/v1/projects', headers: auth_headers(gerente)

      ids = JSON.parse(response.body).map { |p| p['id'] }
      expect(ids).to eq([projeto_a.id])
    end

    # 7.1.1 / D-29 — no legado `Project.where(id: params[:project_id])`
    # SUBSTITUÍA a lista escopada por participação.
    it 'com `project_id` de um projeto de que NÃO participa devolve vazio' do
      get '/api/v1/projects', params: { project_id: projeto_b.id }, headers: auth_headers(gerente)

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)).to be_empty
    end

    it 'com `importing_id` de outro projeto continua limitado à participação' do
      projeto_b.update_column(:importing_id, 42)

      get '/api/v1/projects', params: { importing_id: 42 }, headers: auth_headers(gerente)
      expect(JSON.parse(response.body)).to be_empty
    end

    # DEC-99, nos DOIS sentidos.
    it 'OG e Admin enxergam TODOS os projetos; o Gerente NÃO' do
      [UserType.og, UserType.admin].each do |tipo|
        usuario = create(:user, user_type: tipo)
        get '/api/v1/projects', headers: auth_headers(usuario)
        ids = JSON.parse(response.body).map { |p| p['id'] }
        expect(ids).to include(projeto_a.id, projeto_b.id), "#{tipo.name} não enxergou todos"
      end

      get '/api/v1/projects', headers: auth_headers(gerente)
      expect(JSON.parse(response.body).map { |p| p['id'] }).to eq([projeto_a.id])
    end

    it '`order_mode=dash` ordena por `updated_at` asc. e IGNORA `q`' do
      get '/api/v1/projects', params: { order_mode: 'dash', q: 'inexistente' },
                              headers: auth_headers(gerente)
      expect(JSON.parse(response.body).map { |p| p['id'] }).to eq([projeto_a.id])
    end

    it 'pagina de verdade' do
      og = create(:user, user_type: UserType.og)
      get '/api/v1/projects', params: { per_page: 1 }, headers: auth_headers(og)

      expect(JSON.parse(response.body).size).to eq(1)
      expect(response.headers['X-Total-Count']).to eq('2')
    end
  end

  describe 'GET /api/v1/projects/autocomplete' do
    # BE-083 — o legado usava `LIKE` cru: no Postgres, digitar minúscula não
    # achava nada.
    it 'acha com o termo em MINÚSCULA (ILIKE) e respeita o limite' do
      get '/api/v1/projects/autocomplete', params: { q: 'alfa' }, headers: auth_headers(gerente)

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body).map { |p| p['id'] }).to eq([projeto_a.id])
    end
  end

  describe 'POST /api/v1/projects' do
    it 'sem responsável: o projeto pertence a quem criou, com participação' do
      post '/api/v1/projects', params: { name: 'Gama Empreendimentos' }, headers: auth_headers(gerente)

      expect(response).to have_http_status(201)
      criado = Project.find(JSON.parse(response.body)['id'])
      expect(criado.user_id).to eq(gerente.id)
      expect(Membership.exists?(project_id: criado.id, user_id: gerente.id)).to be(true)
    end

    it 'o slug é derivado do nome e a empresa padrão é criada' do
      post '/api/v1/projects', params: { name: 'Delta Participações' }, headers: auth_headers(gerente)

      criado = Project.find(JSON.parse(response.body)['id'])
      expect(criado.slug).to eq('delta-participacoes')
      expect(criado.integration_key).to eq('delta_participacoes')
      expect(Company.for_project(criado).pluck(:title)).to eq(['Empresa Padrão'])
    end

    # 7.4.1 / **D-38** — o legado montava `username` e senha em TEXTO PLANO num
    # hash para a view. Nenhuma senha é montada, exibida ou enviada.
    it 'com responsável NOVO envia link de convite e a resposta não contém senha nem username' do
      expect(Auth::InviteService).to receive(:call).and_call_original

      post '/api/v1/projects',
           params: { name: 'Epsilon SPE', responsible_mode: 'new',
                     responsible_name: 'Maria Souza', responsible_email: 'maria@exemplo.com' },
           headers: auth_headers(gerente)

      expect(response).to have_http_status(201)
      expect(response.body).not_to match(/password|senha|username/i)

      criado = Project.find(JSON.parse(response.body)['id'])
      convidada = User.find_by(email: 'maria@exemplo.com')
      expect(convidada).to be_present
      expect(criado.responsible_id).to eq(convidada.id)
      # O link de uso único é o caminho de entrada; não há credencial montada.
      expect(LoginCode.where(user_id: convidada.id).where.not(link_token: nil)).to be_present
    end

    # 7.4.2 / DC-14 — no legado o criador ficava de fora do próprio projeto.
    it 'com responsável EXISTENTE: a posse vai para ele e o CRIADOR mantém participação' do
      alvo = create(:user, user_type: UserType.colaborador)

      post '/api/v1/projects',
           params: { name: 'Zeta Urbanismo', responsible_mode: 'existing', responsible_user_id: alvo.id },
           headers: auth_headers(gerente)

      expect(response).to have_http_status(201)
      criado = Project.find(JSON.parse(response.body)['id'])
      expect(criado.user_id).to eq(alvo.id)
      expect(Membership.exists?(project_id: criado.id, user_id: alvo.id)).to be(true)
      expect(Membership.exists?(project_id: criado.id, user_id: gerente.id)).to be(true)
    end

    it 'responsável EXISTENTE em branco responde 422, não o 500 do legado' do
      post '/api/v1/projects',
           params: { name: 'Eta Holding', responsible_mode: 'existing', responsible_user_id: '' },
           headers: auth_headers(gerente)

      expect(response).to have_http_status(422)
    end

    it 'nome repetido responde 422 (o legado validava e não tinha índice)' do
      post '/api/v1/projects', params: { name: 'Alfa Incorporadora' }, headers: auth_headers(gerente)
      expect(response).to have_http_status(422)
    end

    it 'enfileira o job de membros padrão com identificador PRÓPRIO (BE-088)' do
      adaptador = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      begin
        expect { post '/api/v1/projects', params: { name: 'Theta SPE' }, headers: auth_headers(gerente) }
          .to have_enqueued_job(LinkDefaultMembersJob)
      ensure
        ActiveJob::Base.queue_adapter = adaptador
      end
    end
  end

  describe 'PUT /api/v1/projects/:id' do
    # 7.4.3 / DC-17 — no legado `set_smart_id` rodava em TODO
    # `before_validation`: renomear o projeto mudava o slug e as URLs.
    it 'renomear o projeto NÃO altera o slug' do
      antes = projeto_a.slug

      put "/api/v1/projects/#{projeto_a.id}", params: { name: 'Alfa Incorporadora S.A.' },
                                              headers: auth_headers(gerente)

      expect(response).to have_http_status(200)
      expect(projeto_a.reload.name).to eq('Alfa Incorporadora S.A.')
      expect(projeto_a.slug).to eq(antes)
    end

    it 'mandar `slug` no corpo não muda o slug — o campo nem é declarado' do
      antes = projeto_a.slug
      put "/api/v1/projects/#{projeto_a.id}", params: { slug: 'novo-slug' },
                                              headers: auth_headers(gerente)
      expect(projeto_a.reload.slug).to eq(antes)
    end

    it 'projeto de que não participa responde 404 e não é alterado' do
      put "/api/v1/projects/#{projeto_b.id}", params: { name: 'Invadido' }, headers: auth_headers(gerente)

      expect(response).to have_http_status(404)
      expect(projeto_b.reload.name).to eq('Beta Construtora')
    end

    it 'a marca de BI NÃO muda pelo update (DC-16 — tem endpoint próprio)' do
      put "/api/v1/projects/#{projeto_a.id}", params: { name: 'Alfa', has_bi: true },
                                              headers: auth_headers(gerente)
      expect(projeto_a.reload.has_bi).to be(false)
    end
  end

  describe 'as duas marcas' do
    it 'grava a marca de gestão e a de BI em campos SEPARADOS' do
      patch "/api/v1/projects/#{projeto_a.id}/bi", params: { value: true },
                                                   headers: auth_headers(gerente)
      expect(response).to have_http_status(200)
      expect(projeto_a.reload.has_bi).to be(true)
      expect(projeto_a.has_safegold_management).to be(true)

      patch "/api/v1/projects/#{projeto_a.id}/safegold_management", params: { value: false },
                                                                    headers: auth_headers(gerente)
      expect(projeto_a.reload.has_safegold_management).to be(false)
      expect(projeto_a.has_bi).to be(true)
    end

    # **DEC-112 / DB-051** — a marca da empresa é CARIMBADA em coluna própria, e
    # `companies` é a ÚNICA filha ressincronizada quando a marca do projeto muda
    # (`project.rb:298-303`).
    it 'carimba a marca na empresa e a RESSINCRONIZA quando a do projeto muda' do
      empresa = create(:company, project: projeto_a)
      expect(Company.column_names).to include('has_safegold_management')
      expect(empresa.has_safegold_management).to be(true)

      patch "/api/v1/projects/#{projeto_a.id}/safegold_management", params: { value: false },
                                                                    headers: auth_headers(gerente)
      expect(response).to have_http_status(200)
      expect(empresa.reload.has_safegold_management).to be(false)
    end

    # **D-30, replicado de propósito (DEC-112).** O `update_all` do legado toca
    # SÓ `companies`. Um limite de risco já gravado fica com o carimbo velho
    # para sempre — é a foto do momento que o consumidor externo (BI) quer.
    it 'NÃO ressincroniza as demais filhas — o limite fica com o carimbo velho' do
      empresa = create(:company, project: projeto_a)
      limite = create(:risk_control, project: projeto_a, company: empresa)
      expect(limite.has_safegold_management).to be(true)

      patch "/api/v1/projects/#{projeto_a.id}/safegold_management", params: { value: false },
                                                                    headers: auth_headers(gerente)
      expect(response).to have_http_status(200)
      expect(empresa.reload.has_safegold_management).to be(false)
      expect(limite.reload.has_safegold_management).to be(true)
    end
  end

  describe 'DELETE /api/v1/projects/:id' do
    # 7.4.4 / D-24 — o legado respondia `:ok` e o JS redirecionava dizendo
    # "removido com sucesso" sem ter removido.
    it 'com empresa vinculada responde 422 e o projeto PERMANECE' do
      create(:company, project: projeto_a)

      delete "/api/v1/projects/#{projeto_a.id}", headers: auth_headers(gerente)

      expect(response).to have_http_status(422)
      expect(Project.exists?(projeto_a.id)).to be(true)
    end

    # A mensagem é pt-BR e **nomeia o vínculo com a contagem**.
    #
    # Apareceu rodando, na tela: com `dependent: :restrict_with_error` o texto
    # era a frase genérica do Rails, com o nome da ASSOCIAÇÃO em inglês no meio
    # do português — "Não é possível excluir o registro pois existem companies
    # dependentes". `rspec` passava, porque o teste só olhava o status.
    it 'a mensagem do 422 nomeia o vínculo em pt-BR, com a contagem' do
      create_list(:company, 2, project: projeto_a)
      create(:provider, project: projeto_a)

      delete "/api/v1/projects/#{projeto_a.id}", headers: auth_headers(gerente)

      corpo = JSON.parse(response.body)
      expect(corpo['message']).to include('2 empresa(s)')
      expect(corpo['message']).to include('1 fornecedor(es)')
      expect(corpo['message']).not_to include('companies')
      expect(corpo['message']).not_to include('providers')
    end

    it 'sem dependente remove de verdade' do
      vazio = create_project_with_owner(gerente, slug: 'vazio', name: 'Projeto Vazio')

      delete "/api/v1/projects/#{vazio.id}", headers: auth_headers(gerente)
      expect(response).to have_http_status(200).or have_http_status(204)
      expect(Project.exists?(vazio.id)).to be(false)
    end

    # 7.4.6 / BE-092 — o projeto de treinamento não é removível, só limpo.
    it 'o projeto de treinamento NÃO é removível' do
      projeto_a.update_column(:is_sandbox, true)

      delete "/api/v1/projects/#{projeto_a.id}", headers: auth_headers(gerente)

      expect(response).to have_http_status(422)
      expect(response.body).to include('treinamento')
      expect(Project.exists?(projeto_a.id)).to be(true)
    end
  end

  # 7.4.6 / BE-092 — o reset.
  describe 'POST /api/v1/projects/:id/reset' do
    before { projeto_a.update_column(:is_sandbox, true) }

    it 'apaga os dados do projeto e o devolve ao estado inicial, preservando identidade' do
      create(:company, project: projeto_a, title: 'Sujeira')
      create(:provider, project: projeto_a)
      portador = create(:carrier)
      create(:project_guarantee, project: projeto_a, carrier: portador)
      nome_antes = projeto_a.name
      slug_antes = projeto_a.slug
      chave_antes = projeto_a.integration_key

      post "/api/v1/projects/#{projeto_a.id}/reset", headers: auth_headers(gerente)

      expect(response).to have_http_status(200)
      projeto_a.reload
      # A identidade é preservada — é o MESMO projeto.
      expect(projeto_a.name).to eq(nome_antes)
      expect(projeto_a.slug).to eq(slug_antes)
      expect(projeto_a.integration_key).to eq(chave_antes)
      # E o dado some, menos a empresa padrão que volta.
      expect(Company.for_project(projeto_a).pluck(:title)).to eq(['Empresa Padrão'])
      expect(Provider.for_project(projeto_a)).to be_empty
      expect(ProjectGuarantee.for_project(projeto_a)).to be_empty
      expect(ProjectToCarrierConnection.for_project(projeto_a)).to be_empty
    end

    # D-26 — o segmento vem da CHAVE, nunca de um id fixo.
    it 'resolve o segmento por chave de integração, e aceita a ausência dele' do
      treinamento = create(:segment, title: 'Treinamento')
      expect(treinamento.integration_key).to eq('treinamento')

      post "/api/v1/projects/#{projeto_a.id}/reset", headers: auth_headers(gerente)
      expect(projeto_a.reload.segment_id).to eq(treinamento.id)

      # E o segmento em uso passa a ser inexcluível — é a regra da S3 valendo
      # sobre o vínculo que esta fatia acabou de criar.
      expect(treinamento.destroy).to be(false)
    end

    it 'sem o segmento "treinamento" cadastrado, a limpeza funciona e deixa NULO' do
      # Melhor sem segmento do que apontando para o primeiro registro que
      # sobrou na tabela — que é literalmente o que o `segment_id = 1` do legado
      # fazia (D-26).
      expect(Segment.find_by(integration_key: 'treinamento')).to be_nil
      projeto_a.update_column(:segment_id, create(:segment).id)

      post "/api/v1/projects/#{projeto_a.id}/reset", headers: auth_headers(gerente)

      expect(response).to have_http_status(200)
      expect(projeto_a.reload.segment_id).to be_nil
    end

    it 'recusa com 422 quando o projeto NÃO é de treinamento' do
      projeto_a.update_column(:is_sandbox, false)

      post "/api/v1/projects/#{projeto_a.id}/reset", headers: auth_headers(gerente)
      expect(response).to have_http_status(422)
    end

    it 'projeto de outro escopo responde 404, não 422' do
      post "/api/v1/projects/#{projeto_b.id}/reset", headers: auth_headers(gerente)
      expect(response).to have_http_status(404)
    end
  end

  # 7.1.9 / BE-100 / DC-18 — aba informativa: só o que o solicitante já veria.
  describe 'GET /api/v1/users/:id/projects' do
    it 'mostra a interseção entre a participação do alvo e a visibilidade do solicitante' do
      alvo = create(:user, user_type: UserType.colaborador)
      Membership.create!(project: projeto_a, user: alvo, role: 'participante')
      Membership.create!(project: projeto_b, user: alvo, role: 'participante')

      get "/api/v1/users/#{alvo.id}/projects", headers: auth_headers(gerente)
      expect(JSON.parse(response.body).map { |p| p['id'] }).to eq([projeto_a.id])

      og = create(:user, user_type: UserType.og)
      get "/api/v1/users/#{alvo.id}/projects", headers: auth_headers(og)
      expect(JSON.parse(response.body).map { |p| p['id'] }).to contain_exactly(projeto_a.id, projeto_b.id)
    end
  end

  # BE-084 — filtragem por hierarquia no SERVIDOR, nos dois sentidos.
  describe 'GET /api/v1/projects/responsible_candidates' do
    it 'o Gerente não vê OG nem Admin entre os candidatos; o OG vê' do
      admin = create(:user, user_type: UserType.admin)
      colaborador = create(:user, user_type: UserType.colaborador)

      get '/api/v1/projects/responsible_candidates', headers: auth_headers(gerente)
      ids = JSON.parse(response.body).map { |u| u['id'] }
      expect(ids).to include(colaborador.id)
      expect(ids).not_to include(admin.id)

      og = create(:user, user_type: UserType.og)
      get '/api/v1/projects/responsible_candidates', headers: auth_headers(og)
      expect(JSON.parse(response.body).map { |u| u['id'] }).to include(admin.id)
    end
  end

  # ActionText — `reuse` puro. O único trabalho novo é bloquear anexo no
  # servidor (7.4.9): o ActionText os aceita por padrão e o legado bloqueava só
  # no cliente (`trix-file-accept`).
  describe 'observação de disponibilidade (ActionText)' do
    it 'grava e devolve HTML e texto puro' do
      put "/api/v1/projects/#{projeto_a.id}",
          params: { availability_note: '<div>Fecha dia <strong>25</strong></div>' },
          headers: auth_headers(gerente)

      corpo = JSON.parse(response.body)
      expect(corpo['availability_note_html']).to include('<strong>25</strong>')
      expect(corpo['availability_note_text']).to include('Fecha dia 25')
    end

    it 'RECUSA anexo embutido no corpo do ActionText' do
      put "/api/v1/projects/#{projeto_a.id}",
          params: { availability_note: '<action-text-attachment sgid="x"></action-text-attachment>' },
          headers: auth_headers(gerente)

      expect(response).to have_http_status(422)
      expect(projeto_a.reload.availability_note.body.to_s).not_to include('action-text-attachment')
    end
  end
end

# ---------------------------------------------------------------------------
# Achado do usuário (26/08/2026): o detalhe de projeto caía inteiro com
# "Cannot read properties of null (reading 'trim')".
#
# A causa não estava na tela: `availability_note_text` devolvia `nil` para nota
# vazia enquanto o irmão `availability_note_html` devolvia `""`. Dois campos da
# MESMA nota discordando sobre "vazio", com o tipo do frontend dizendo `string`
# para os dois — `tsc` verde, tela quebrada.
# ---------------------------------------------------------------------------
RSpec.describe 'API::V1::Projects — nota de disponibilidade vazia', type: :request do
  before { UserType.seed_default_types! }

  let(:dono) { create(:user, :gerente) }
  let!(:projeto) { create_project_with_owner(dono) }

  it 'devolve STRING VAZIA, nunca nil, quando a nota nunca foi escrita' do
    get "/api/v1/projects/#{projeto.id}", headers: auth_headers(dono, project: projeto)

    corpo = JSON.parse(response.body)
    expect(response).to have_http_status(:ok)
    expect(corpo['availability_note_text']).to eq('')
    expect(corpo['availability_note_text']).not_to be_nil
  end

  it 'os dois campos da mesma nota concordam sobre o que é "vazio"' do
    get "/api/v1/projects/#{projeto.id}", headers: auth_headers(dono, project: projeto)

    corpo = JSON.parse(response.body)
    # A assimetria entre eles é o defeito; o par é o que impede que volte.
    expect(corpo['availability_note_text']).to be_a(String)
    expect(corpo['availability_note_html']).to be_a(String)
  end

  it 'preserva o texto quando a nota existe' do
    projeto.update!(availability_note: '<div>Vencimento no dia 10.</div>')

    get "/api/v1/projects/#{projeto.id}", headers: auth_headers(dono, project: projeto)

    expect(JSON.parse(response.body)['availability_note_text']).to include('Vencimento no dia 10.')
  end
end

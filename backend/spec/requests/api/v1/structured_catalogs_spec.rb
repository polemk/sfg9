# frozen_string_literal: true

require 'rails_helper'

# S8 / **BE-296**…**BE-299**, **BE-308**, **BE-725**…**BE-729**, tarefas 12.6,
# 12.7 e 12.8.
#
# Os **dois catálogos GLOBAIS** da unidade. Nenhum endpoint aqui chama
# `current_project!` — um tipo de operação estruturada vale para todos os
# projetos, e escondê-lo por projeto quebraria a remuneração que já aponta para
# ele (contrato C1, regra 4).
#
# É aqui que os **dois lados** da hierarquia (C3) se separam de verdade nesta
# unidade: a matriz dá `CRUD CRUD CRUD R` aos dois catálogos, então o
# Colaborador **lê** (para o select subir populado, DEC-18.4) e **não escreve**.
RSpec.describe 'API V1 Structured catalogs', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:gerente) { create(:user, user_type: UserType.gerente) }
  let(:colaborador) { create(:user, user_type: UserType.colaborador) }

  # ====================================================================
  # Tipos de operação estruturada
  # ====================================================================
  describe 'structured_operation_types' do
    let!(:ativo) { create(:structured_operation_type, title: 'Fomento X') }
    let!(:inativo) { create(:structured_operation_type, :inativo, title: 'Descontinuado') }

    it 'BE-296 — o filtro de ativo é OPCIONAL: tipo desativado APARECE na administração' do
      # No legado a listagem era sempre `.active`, com o SQL literal
      # `where('is_active = 1 ')`. Consequência: desativar um tipo o fazia
      # sumir da tela e **não havia como reativá-lo pela UI** — só por SQL.
      get '/api/v1/structured_operation_types', headers: auth_headers(gerente)

      titulos = response.parsed_body.map { |t| t['title'] }
      expect(titulos).to include('Fomento X', 'Descontinuado')

      get '/api/v1/structured_operation_types', params: { active: true }, headers: auth_headers(gerente)
      expect(response.parsed_body.map { |t| t['title'] }).to eq(['Fomento X'])
    end

    it 'BE-297 — a chave é derivada do título no create, e é ÚNICA no banco' do
      post '/api/v1/structured_operation_types', params: { title: 'Auto Liquidável' },
                                                 headers: auth_headers(gerente), as: :json

      expect(response).to have_http_status(201)
      expect(response.parsed_body['integration_key']).to eq('auto_liquidavel')

      # Dois títulos DIFERENTES que derivam a MESMA chave: no legado colidiam em
      # silêncio, e é a chave que a integração usa.
      post '/api/v1/structured_operation_types', params: { title: 'Auto  Liquidavel' },
                                                 headers: auth_headers(gerente), as: :json
      expect(response).to have_http_status(422)
    end

    it 'BE-298 — `title` e `integration_key` são recusados na edição, NO SERVIDOR' do
      put "/api/v1/structured_operation_types/#{ativo.id}", params: { title: 'Renomeado' },
                                                            headers: auth_headers(gerente), as: :json

      expect(response).to have_http_status(422)
      expect(response.parsed_body['message']).to include('não podem ser alterados')
      expect(ativo.reload.title).to eq('Fomento X')
    end

    it 'a edição do que É editável funciona' do
      put "/api/v1/structured_operation_types/#{ativo.id}", params: { is_active: false },
                                                            headers: auth_headers(gerente), as: :json

      expect(response).to have_http_status(200)
      expect(ativo.reload.is_active).to be(false)
    end

    it 'BE-299 — tipo SEMEADO (`is_default`) responde 422, com a frase dizendo por quê' do
      # Os QUATRO tipos semeados são `is_default`, logo nenhum é removível pela
      # tela. Replicado — mas dizendo o motivo, em vez de o botão sumir.
      semeado = create(:structured_operation_type, :semeado, title: 'Semeado')

      delete "/api/v1/structured_operation_types/#{semeado.id}", headers: auth_headers(gerente)

      expect(response).to have_http_status(422)
      expect(response.parsed_body['message']).to include('tipo padrão')
      expect(StructuredOperationType.exists?(semeado.id)).to be(true)
    end

    it 'BE-299 — tipo EM USO por operação responde 422 REAL, não 200' do
      projeto = create_project_with_owner(gerente, slug: 'cat-uso')
      create(:structured_operation, project: projeto, company: create(:company, project: projeto),
                                    operation_type: ativo)

      delete "/api/v1/structured_operation_types/#{ativo.id}", headers: auth_headers(gerente)

      expect(response).to have_http_status(422)
      expect(StructuredOperationType.exists?(ativo.id)).to be(true)
    end

    it 'tipo livre é excluído' do
      delete "/api/v1/structured_operation_types/#{inativo.id}", headers: auth_headers(gerente)

      expect(response).to have_http_status(200)
      expect(StructuredOperationType.exists?(inativo.id)).to be(false)
    end

    it 'id malformado responde 404, não 500 (`PG::InvalidTextRepresentation`)' do
      get '/api/v1/structured_operation_types/nao-e-uuid', headers: auth_headers(gerente)
      expect(response).to have_http_status(404)
    end

    it 'C3 — o Colaborador LÊ (DEC-18.4) e NÃO escreve' do
      get '/api/v1/structured_operation_types', headers: auth_headers(colaborador)
      expect(response).to have_http_status(200)

      post '/api/v1/structured_operation_types', params: { title: 'Forjado' },
                                                 headers: auth_headers(colaborador), as: :json
      expect(response).to have_http_status(403)

      delete "/api/v1/structured_operation_types/#{ativo.id}", headers: auth_headers(colaborador)
      expect(response).to have_http_status(403)
    end

    it 'FE-309 — nenhum verbo responde sem JWT' do
      get '/api/v1/structured_operation_types'
      expect(response).to have_http_status(401)

      post '/api/v1/structured_operation_types', params: { title: 'X' }, as: :json
      expect(response).to have_http_status(401)
    end
  end

  # ====================================================================
  # Fontes de recurso — a superfície de ESCRITA que a S6 deixou para cá
  # ====================================================================
  describe 'resource_sources' do
    let!(:fonte) { create(:resource_source, title: 'Caixa S8') }

    it 'BE-726 — `show` de id inexistente responde 404 ESTRUTURADO (no legado, 500)' do
      get "/api/v1/resource_sources/#{SecureRandom.uuid}", headers: auth_headers(gerente)

      expect(response).to have_http_status(404)
      expect(response.parsed_body['message']).to be_present
    end

    it 'BE-727 — cria com a chave derivada do título' do
      post '/api/v1/resource_sources', params: { title: 'Defasagem' },
                                       headers: auth_headers(gerente), as: :json

      expect(response).to have_http_status(201)
      expect(response.parsed_body['integration_key']).to eq('defasagem')
    end

    it 'BE-727 — título duplicado responde 422, não 500' do
      post '/api/v1/resource_sources', params: { title: 'Caixa S8' },
                                       headers: auth_headers(gerente), as: :json
      expect(response).to have_http_status(422)
    end

    it 'BE-728 — a chave é IMUTÁVEL, e renomear o título não a toca' do
      put "/api/v1/resource_sources/#{fonte.id}", params: { integration_key: 'outra' },
                                                  headers: auth_headers(gerente), as: :json
      expect(response).to have_http_status(422)
      expect(response.parsed_body['message']).to include('não pode ser alterada')

      put "/api/v1/resource_sources/#{fonte.id}", params: { title: 'Caixa Renomeada' },
                                                  headers: auth_headers(gerente), as: :json
      expect(response).to have_http_status(200)
      expect(fonte.reload.title).to eq('Caixa Renomeada')
      expect(fonte.integration_key).to eq('caixa_s8')
    end

    it 'BE-729 — fonte EM USO por borderô responde 422 com a dependência (aqui a guarda dispara)' do
      # É o caso em que a guarda realmente vale: a coluna está preenchida em
      # **28.131 de 28.131** linhas de produção. No legado os dois ramos
      # devolviam `:ok` e a lista recarregava como se tivesse excluído.
      projeto = create_project_with_owner(gerente, slug: 'rs-uso')
      create(:receivable_entry, project: projeto, resource_source: fonte)

      delete "/api/v1/resource_sources/#{fonte.id}", headers: auth_headers(gerente)

      expect(response).to have_http_status(422)
      expect(ResourceSource.exists?(fonte.id)).to be(true)
    end

    it 'fonte livre é excluída' do
      delete "/api/v1/resource_sources/#{fonte.id}", headers: auth_headers(gerente)

      expect(response).to have_http_status(200)
      expect(ResourceSource.exists?(fonte.id)).to be(false)
    end

    it 'Q-R19 — a leitura NÃO filtra por ativa por padrão (é o select do borderô)' do
      create(:resource_source, title: 'Aposentada', is_active: false)

      get '/api/v1/resource_sources', headers: auth_headers(gerente)
      expect(response.parsed_body.map { |f| f['title'] }).to include('Aposentada')
    end

    it 'C3 — o Colaborador LÊ e NÃO escreve' do
      get '/api/v1/resource_sources', headers: auth_headers(colaborador)
      expect(response).to have_http_status(200)

      post '/api/v1/resource_sources', params: { title: 'Forjada' },
                                       headers: auth_headers(colaborador), as: :json
      expect(response).to have_http_status(403)
    end
  end

  # ====================================================================
  # 12.8 — os seeds
  # ====================================================================
  describe 'seeds de referência (tarefa 12.8)' do
    it 'rodar duas vezes não duplica, e as 4 chaves de tipo estruturado existem' do
      Seeds::Reference::Runner.call_one!('Seeds::Reference::StructuredOperationTypes')
      Seeds::Reference::Runner.call_one!('Seeds::Reference::StructuredOperationTypes')

      chaves = StructuredOperationType.pluck(:integration_key)
      expect(chaves).to include('fomento', 'comissaria', 'intercompany', 'auto_liquidavel')
      expect(StructuredOperationType.where(integration_key: 'fomento').count).to eq(1)
    end

    it 'os 4 tipos semeados são TODOS `is_default` — logo nenhum é removível' do
      Seeds::Reference::Runner.call_one!('Seeds::Reference::StructuredOperationTypes')

      semeados = StructuredOperationType.where(integration_key: %w[fomento comissaria intercompany auto_liquidavel])
      expect(semeados.count).to eq(4)
      expect(semeados.where(is_default: false)).to be_empty
    end

    it 'as 6 chaves de fonte de recurso existem, e a coexistência não fura a unicidade' do
      Seeds::Reference::Runner.call_one!('Seeds::Reference::ResourceSources')
      # Uma linha "importada do legado" com o mesmo `legacy_id`: a chave natural
      # do seed é `legacy_id`, então a segunda execução reencontra em vez de
      # duplicar por título.
      Seeds::Reference::Runner.call_one!('Seeds::Reference::ResourceSources')

      expect(ResourceSource.where(legacy_id: 1..6).count).to eq(6)
      expect(ResourceSource.find_by(legacy_id: 6).integration_key).to eq('13?_salario')
    end
  end
end

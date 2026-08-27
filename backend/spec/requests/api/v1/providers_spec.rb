# frozen_string_literal: true

require 'rails_helper'

# S4 / 5.2, 7.1.3 — **fornecedores**.
RSpec.describe 'API V1 Providers', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:gerente) { create(:user, user_type: UserType.gerente) }
  let(:outro) { create(:user, user_type: UserType.gerente) }

  let!(:projeto_a) { create_project_with_owner(gerente, slug: 'prov-a', name: 'Fornecedores A') }
  let!(:projeto_b) { create_project_with_owner(outro, slug: 'prov-b', name: 'Fornecedores B') }

  let!(:fornecedor_a) { create(:provider, project: projeto_a, title: 'Cimento Norte') }
  let!(:fornecedor_b) { create(:provider, project: projeto_b, title: 'Aço Sul') }

  describe 'GET /api/v1/providers' do
    it 'traz só os do projeto corrente' do
      get '/api/v1/providers', headers: auth_headers(gerente, project: projeto_a)

      ids = JSON.parse(response.body).map { |p| p['id'] }
      expect(ids).to include(fornecedor_a.id)
      expect(ids).not_to include(fornecedor_b.id)
    end

    # 7.1.3
    it 'com `provider_id` de OUTRO projeto devolve vazio' do
      get '/api/v1/providers', params: { provider_id: fornecedor_b.id },
                               headers: auth_headers(gerente, project: projeto_a)

      expect(JSON.parse(response.body)).to be_empty
    end

    # No legado o escopo era `unless current_user.default_project_id.blank?`:
    # sessão sem projeto padrão recebia **todos os fornecedores de todos os
    # projetos**. Aqui, nunca.
    #
    # O status era 404 e passou a ser 409 quando o `current_project!` deixou de
    # tratar "não escolheu" como "não existe" — a tela dizia "Projeto não
    # encontrado" para quem só não tinha escolhido um. O que a asserção protege
    # não mudou: o catálogo geral não pode sair. E agora o corpo é conferido —
    # antes só o status era, então um 404 COM os fornecedores dentro passaria.
    it 'sem projeto corrente NÃO devolve o catálogo geral — e diz o que fazer' do
      sozinho = create(:user, user_type: UserType.colaborador)

      get '/api/v1/providers', headers: auth_headers(sozinho)

      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)['code']).to eq('PROJECT_NONE_AVAILABLE')
      expect(JSON.parse(response.body)).not_to be_a(Array)
    end

    it 'chave de ordenação desconhecida é ignorada (o legado fazia `nil + " "` → 500)' do
      get '/api/v1/providers', params: { ordering_keys: ['coluna_inventada'] },
                               headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(200)
    end
  end

  describe 'GET /api/v1/providers/:id' do
    it 'a tela de detalhe passa a existir (D-22) e o id alheio responde 404' do
      get "/api/v1/providers/#{fornecedor_a.id}", headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(200)

      get "/api/v1/providers/#{fornecedor_b.id}", headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)
    end
  end

  describe 'POST /api/v1/providers' do
    it 'cria no projeto corrente, com a chave de integração derivada do título' do
      post '/api/v1/providers', params: { title: 'Britagem São José' },
                                headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(201)
      criado = Provider.find(JSON.parse(response.body)['id'])
      expect(criado.project_id).to eq(projeto_a.id)
      expect(criado.integration_key).to eq('britagem_sao_jose')
      expect(criado.user_id).to eq(gerente.id)
    end

    it 'ignora `project_id` do corpo' do
      post '/api/v1/providers', params: { title: 'Forjado', project_id: projeto_b.id },
                                headers: auth_headers(gerente, project: projeto_a)

      expect(Provider.find(JSON.parse(response.body)['id']).project_id).to eq(projeto_a.id)
    end

    # DC-11 — o documento continua OPCIONAL (a regra "ao menos um" estava
    # comentada no model do legado, e a base tem fornecedor sem documento).
    it 'aceita fornecedor SEM documento' do
      post '/api/v1/providers', params: { title: 'Sem documento' },
                                headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(201)
    end

    it 'aceita CNPJ válido e recusa CNPJ com dígito verificador errado' do
      post '/api/v1/providers', params: { title: 'Com CNPJ', document_type: 'CNPJ',
                                          document: '11.222.333/0001-81' },
                                headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(201)
      # Só dígitos no banco: guardar com e sem máscara na mesma coluna é como o
      # legado teve o mesmo fornecedor duas vezes apesar da unicidade.
      expect(Provider.find(JSON.parse(response.body)['id']).document).to eq('11222333000181')

      post '/api/v1/providers', params: { title: 'CNPJ ruim', document_type: 'CNPJ',
                                          document: '11.222.333/0001-99' },
                                headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(422)
      expect(response.body).to include('CNPJ válido')
    end

    it 'aceita CPF válido e recusa CPF inválido' do
      post '/api/v1/providers', params: { title: 'Com CPF', document_type: 'CPF',
                                          document: '529.982.247-25' },
                                headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(201)

      post '/api/v1/providers', params: { title: 'CPF ruim', document_type: 'CPF',
                                          document: '111.111.111-11' },
                                headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(422)
    end

    it 'o mesmo documento no MESMO projeto é 422 — e em OUTRO projeto é permitido' do
      create(:provider, :com_cnpj, project: projeto_a, title: 'Primeiro')

      post '/api/v1/providers', params: { title: 'Repetido', document_type: 'CNPJ',
                                          document: '11222333000181' },
                                headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(422)

      post '/api/v1/providers', params: { title: 'Mesmo doc, outro projeto', document_type: 'CNPJ',
                                          document: '11222333000181' },
                                headers: auth_headers(outro, project: projeto_b)
      expect(response).to have_http_status(201)
    end
  end

  describe 'PUT /api/v1/providers/:id' do
    # BE-062 — no legado a chave em branco passava no update, porque a derivação
    # só rodava `on: [:create]`.
    it 'recusa `integration_key` em branco TAMBÉM no update' do
      put "/api/v1/providers/#{fornecedor_a.id}", params: { integration_key: '' },
                                                  headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(422)
    end

    it 'ignora `project_id` do corpo também aqui (D-23 — o campo escondido movia de projeto)' do
      put "/api/v1/providers/#{fornecedor_a.id}", params: { title: 'Renomeado', project_id: projeto_b.id },
                                                  headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(fornecedor_a.reload.project_id).to eq(projeto_a.id)
    end

    it 'id de outro projeto responde 404 e não altera o alheio' do
      put "/api/v1/providers/#{fornecedor_b.id}", params: { title: 'Invadido' },
                                                  headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)
      expect(fornecedor_b.reload.title).to eq('Aço Sul')
    end
  end

  # 7.4.12 — o anexo. O motor é único (`Attachable` + `config/attachments.yml`);
  # o que se prova aqui é que ele está LIGADO neste recurso e escopado.
  describe 'logo do fornecedor' do
    let(:png) { Rails.root.join('spec/fixtures/files/sample.png') }

    def upload(caminho, tipo)
      Rack::Test::UploadedFile.new(caminho, tipo)
    end

    it 'anexa, expõe a URL e remove' do
      post "/api/v1/providers/#{fornecedor_a.id}/logo",
           params: { file: upload(png, 'image/png') },
           headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)['logo_url']).to be_present
      expect(fornecedor_a.reload.logo).to be_attached

      delete "/api/v1/providers/#{fornecedor_a.id}/logo", headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)['logo_url']).to be_nil
    end

    # O arquivo com extensão de imagem e conteúdo de OUTRA coisa é recusado pelo
    # conteúdo REAL (Marcel/magic bytes), não pelo `Content-Type` declarado.
    it 'recusa arquivo com extensão de imagem e conteúdo que não é imagem' do
      falso = Tempfile.new(['falso', '.png'])
      falso.write("#!/bin/sh\necho nao sou imagem\n")
      falso.rewind

      post "/api/v1/providers/#{fornecedor_a.id}/logo",
           params: { file: Rack::Test::UploadedFile.new(falso.path, 'image/png') },
           headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(422)
      expect(fornecedor_a.reload.logo).not_to be_attached
    ensure
      falso&.close
      falso&.unlink
    end

    it 'anexar em fornecedor de OUTRO projeto responde 404' do
      post "/api/v1/providers/#{fornecedor_b.id}/logo",
           params: { file: upload(png, 'image/png') },
           headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(404)
      expect(fornecedor_b.reload.logo).not_to be_attached
    end
  end

  describe 'DELETE /api/v1/providers/:id' do
    it 'remove o do próprio projeto e recusa o de outro com 404' do
      delete "/api/v1/providers/#{fornecedor_b.id}", headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)
      expect(Provider.exists?(fornecedor_b.id)).to be(true)

      delete "/api/v1/providers/#{fornecedor_a.id}", headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(200)
    end

    # 7.6.3 — cobre DB-071 e BE-063. Mesmo contrato simétrico das empresas:
    # bloquear, nunca cascatear, e **dizer** que bloqueou. No legado a checagem
    # de dependentes do fornecedor não existia para renegociações.
    it 'com renegociações responde 422 e a RENEGOCIAÇÃO permanece' do
      reneg = create(:renegotiation, project: projeto_a, provider: fornecedor_a)

      delete "/api/v1/providers/#{fornecedor_a.id}", headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)['error']).to include('renegocia')
      expect(Provider.exists?(fornecedor_a.id)).to be(true)
      expect(Renegotiation.exists?(reneg.id)).to be(true)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

# S13 / OPS-491, OPS-492 — leitura de anexo: **autoriza primeiro, assina depois**.
#
# O que estes exemplos impedem de voltar: no legado o binário morava em
# `public/system/:attachment/:id/...`, servido como estático, com URL adivinhável e
# sem autenticação nenhuma (D-82). A base ai9 repete o padrão no
# `AssetsProxyController` (flag F-10). Anexo de renegociação é documento financeiro.
RSpec.describe 'API::V1::Attachments' do
  let(:png) { Rails.root.join('spec/fixtures/files/sample.png') }

  def attach_project_avatar(project)
    project.avatar.attach(io: File.open(png), filename: 'logo.png', content_type: 'image/png')
    project.save!
    Sfg::Attachments.describe(project.avatar.attachment)[:id]
  end

  describe 'GET /api/v1/attachments/limits' do
    it 'devolve os números do catálogo CFG-02, para que a tela não tenha número escrito nela' do
      user = create(:user)
      get '/api/v1/attachments/limits', headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      # A chave mudou para `renegotiation_attachment.file` quando a S9 entregou o
      # domínio (uma LINHA por arquivo, com título e autor). Os NÚMEROS são os
      # mesmos, que é o que este exemplo existe para garantir.
      reneg = body.dig('attachments', 'renegotiation_attachment', 'file')

      # Os dois números do `SFG::Metadata` do legado, que lá só existiam no
      # JavaScript da tela.
      expect(reneg['max_files']).to eq(4)
      expect(reneg['max_size_megabytes']).to eq(5)
      # `multiple` é falso porque a LINHA tem um binário; o teto de 4 é por
      # renegociação, e é `max_files` que a tela lê para escrever "máximo de 4".
      expect(reneg['multiple']).to be(false)
      expect(body['url_expires_in_seconds']).to eq(300)
    end

    it 'exige sessão' do
      get '/api/v1/attachments/limits'
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/attachments/:signed_id' do
    it 'emite URL assinada COM PRAZO para quem participa do projeto' do
      owner = create(:user)
      project = create_project_with_owner(owner)
      signed_id = attach_project_avatar(project)

      get "/api/v1/attachments/#{signed_id}", headers: auth_headers(owner, project: project)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['filename']).to eq('logo.png')
      expect(body['url']).to be_present
      expect(body['expires_at']).to be_present
      # A URL do ActiveStorage carrega a expiração assinada; sem prazo ela viraria
      # link compartilhável permanente, que é exatamente o D-82.
      expect(body['url']).to include('/rails/active_storage/')
    end

    it 'responde 404 — e NÃO 403 — para quem não participa do projeto' do
      owner = create(:user)
      project = create_project_with_owner(owner)
      signed_id = attach_project_avatar(project)
      intruder = create(:user, :colaborador)

      get "/api/v1/attachments/#{signed_id}", headers: auth_headers(intruder)

      # 403 diria "este anexo existe, você é que não pode". O endpoint viraria um
      # oráculo de existência — mesma razão de `current_project!` responder 404.
      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)['code']).to eq('ATTACHMENT_NOT_FOUND')
    end

    it 'responde 404 para identificador forjado ou adulterado' do
      user = create(:user)
      get '/api/v1/attachments/nao-e-um-token-assinado', headers: auth_headers(user)
      expect(response).to have_http_status(:not_found)
    end

    it 'exige sessão' do
      owner = create(:user)
      project = create_project_with_owner(owner)
      signed_id = attach_project_avatar(project)

      get "/api/v1/attachments/#{signed_id}"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/attachments/:signed_id/variant' do
    it 'emite URL do derivado declarado' do
      owner = create(:user)
      project = create_project_with_owner(owner)
      signed_id = attach_project_avatar(project)

      get "/api/v1/attachments/#{signed_id}/variant", params: { variant: 'thumb' },
                                                      headers: auth_headers(owner, project: project)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['url']).to be_present
    end

    it 'recusa derivado que não está no catálogo' do
      owner = create(:user)
      project = create_project_with_owner(owner)
      signed_id = attach_project_avatar(project)

      get "/api/v1/attachments/#{signed_id}/variant", params: { variant: 'gigante' },
                                                      headers: auth_headers(owner, project: project)

      expect(response).to have_http_status(:not_found)
    end
  end
end

# S13 / OPS-493 — o avatar do usuário sai de `public/uploads/avatars/`.
RSpec.describe 'API::V1::Users avatar' do
  let(:png) { Rails.root.join('spec/fixtures/files/sample.png') }
  let(:fake) { Rails.root.join('spec/fixtures/files/fake.png') }

  def upload(path, type)
    Rack::Test::UploadedFile.new(path.to_s, type)
  end

  it 'anexa o avatar do próprio usuário e devolve `avatar_url` — mesmo nome de campo de antes' do
    user = create(:user, :colaborador)

    post "/api/v1/users/#{user.id}/avatar", params: { file: upload(png, 'image/png') },
                                            headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['avatar_url']).to be_present
    # O binário NÃO vai mais para `public/uploads`, servido como estático sem auth.
    expect(body['avatar_url']).not_to include('/uploads/avatars/')
    expect(user.reload.avatar).to be_attached
  end

  it 'recusa arquivo que mente sobre o próprio conteúdo, com mensagem legível' do
    user = create(:user, :colaborador)

    post "/api/v1/users/#{user.id}/avatar", params: { file: upload(fake, 'image/png') },
                                            headers: auth_headers(user)

    # O endpoint antigo (`api/v1/uploads.rb:31`) aceitaria: ele só olha o
    # `Content-Type` que o cliente declarou.
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)['code']).to eq('ATTACHMENT_REJECTED')
    expect(user.reload.avatar).not_to be_attached
  end

  it 'não deixa um colaborador trocar o avatar de outra pessoa' do
    dono = create(:user, :colaborador)
    intruso = create(:user, :colaborador)

    post "/api/v1/users/#{dono.id}/avatar", params: { file: upload(png, 'image/png') },
                                            headers: auth_headers(intruso)

    expect(response).to have_http_status(:forbidden)
    expect(dono.reload.avatar).not_to be_attached
  end

  it 'remove o avatar e volta a expor a URL do OAuth, se houver' do
    user = create(:user, :colaborador, avatar_url: 'https://exemplo.test/foto.png')
    user.avatar.attach(io: File.open(png), filename: 's.png', content_type: 'image/png')
    user.save!

    delete "/api/v1/users/#{user.id}/avatar", headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['avatar_url']).to eq('https://exemplo.test/foto.png')
  end

  # S1 / tarefa 9.3.7 — a **outra metade** do requisito. O exemplo do conteúdo
  # forjado já existia; o do teto não, e ele é o que prova que o limite de 3 MB do
  # `config/attachments.yml` é aplicado pelo SERVIDOR.
  #
  # O legado validava 4 arquivos / 5 MB só no JavaScript da tela, e a base ai9 não
  # tinha limite nenhum no endpoint antigo — os dois casos passam por aqui.
  it 'recusa arquivo acima do teto declarado no catálogo, com o número do catálogo na mensagem' do
    user = create(:user, :colaborador)
    limite = Sfg::Attachments.spec_for('user', :avatar).max_size_bytes

    grande = Tempfile.new(['grande', '.png'])
    # Cabeçalho PNG de verdade seguido de enchimento: o arquivo é uma imagem
    # legítima aos olhos do detector, e o que o reprova é o TAMANHO — senão o
    # exemplo passaria pelo motivo errado.
    grande.binmode
    grande.write(File.binread(png))
    grande.write("\0" * (limite + 1))
    grande.rewind

    post "/api/v1/users/#{user.id}/avatar",
         params: { file: Rack::Test::UploadedFile.new(grande.path, 'image/png') },
         headers: auth_headers(user)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)['message']).to include((limite / 1.megabyte).to_s)
    expect(user.reload.avatar).not_to be_attached
  ensure
    grande&.close!
  end
end

# frozen_string_literal: true

require 'rails_helper'

# `POST /api/v1/uploads/avatar` é o endpoint **da base ai9**, não o do Safegold — o
# avatar do produto sai por `POST /api/v1/users/:id/avatar` (ver
# `spec/requests/api/v1/attachments_spec.rb`). Ele continua montado porque duas telas
# do assistente interno o consomem.
#
# Estes exemplos travam as duas linhas de segurança que a S1 acrescentou: tipo pelo
# conteúdo real (F-09) e teto de tamanho no servidor. Sem eles a correção volta atrás
# no primeiro refactor, porque nada aponta que ela existe de propósito.
RSpec.describe 'API V1 Uploads', type: :request do
  let!(:og_user) { create(:user, :og) }
  let(:token) { Auth::TokenService.new(og_user).generate_tokens[:token] }
  let(:headers) { { 'Authorization' => "Bearer #{token}" } }

  let(:png)  { Rails.root.join('spec/fixtures/files/sample.png') }
  let(:fake) { Rails.root.join('spec/fixtures/files/fake.png') }

  def upload(path, declared_type)
    Rack::Test::UploadedFile.new(path.to_s, declared_type)
  end

  # ⚠ **Só apaga o que ESTE exemplo criou.**
  #
  # A primeira versão deste bloco fazia `Dir.glob('public/uploads/avatars/*')` e removia
  # tudo — e apagou **19 arquivos versionados** do repositório na primeira execução. O
  # diretório é o de verdade (a suíte roda com o `Rails.root` do app), não um sandbox.
  # A lista é tirada ANTES do exemplo e a diferença é o que sai.
  let(:pasta) { Rails.root.join('public/uploads/avatars') }
  let!(:antes) { Dir.glob(pasta.join('*')) }

  after { (Dir.glob(pasta.join('*')) - antes).each { |f| FileUtils.rm_f(f) } }

  # "Nada foi gravado" também passa a ser medido contra o estado inicial, e não contra
  # um diretório que se supõe vazio.
  def gravados
    Dir.glob(pasta.join('*')) - antes
  end

  describe 'POST /api/v1/uploads/avatar' do
    it 'requires authentication' do
      post '/api/v1/uploads/avatar'
      expect(response).to have_http_status(401)
    end

    it 'accepts a real image' do
      post '/api/v1/uploads/avatar', params: { file: upload(png, 'image/png') }, headers: headers

      expect(response).to have_http_status(201)
      expect(JSON.parse(response.body)['url']).to include('/uploads/avatars/')
    end

    # F-09 — o exemplo que separa o endpoint corrigido do anterior. Antes,
    # `ct.start_with?('image/')` olhava o rótulo do cliente e este arquivo passava.
    it 'rejects a file that lies about its own content, even with a forged Content-Type' do
      post '/api/v1/uploads/avatar', params: { file: upload(fake, 'image/png') }, headers: headers

      expect(response).to have_http_status(415)
      expect(JSON.parse(response.body)['error']).to eq('unsupported_media_type')
      expect(gravados).to be_empty
    end

    it 'enforces the size cap on the server' do
      stub_const('Api::V1::Uploads::MAX_UPLOAD_BYTES', 10)

      post '/api/v1/uploads/avatar', params: { file: upload(png, 'image/png') }, headers: headers

      expect(response).to have_http_status(413)
      expect(gravados).to be_empty
    end
  end
end

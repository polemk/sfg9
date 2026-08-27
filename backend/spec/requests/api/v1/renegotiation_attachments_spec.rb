# frozen_string_literal: true

require 'rails_helper'

# S9 — **anexos da renegociação**: o D-82 inteiro, fechado e provado.
#
# Cobre as tarefas 4.20 (cinco asserções de segurança) e 4.21 (limites).
#
# ⚠ **DEC-84 / DEC-102 — o que este arquivo NÃO prova.** Ele prova o RECURSO com
# arquivos novos. A **carga do acervo de produção** (os binários em
# `public/system/` do servidor legado) depende de uma cópia que o usuário ainda
# não forneceu, e ficou para depois da apresentação. Ver a tarefa 5.3, que
# permanece aberta declarando o bloqueio.
RSpec.describe 'API::V1::RenegotiationAttachments' do
  let(:autor) { create(:user, :gerente) }
  let(:project) { create_project_with_owner(autor) }
  let(:headers) { auth_headers(autor, project: project) }
  let(:renegotiation) do
    create(:renegotiation, project: project,
                           provider: create(:provider, project: project),
                           company: create(:company, project: project))
  end
  let(:base) { "/api/v1/renegotiations/#{renegotiation.id}/attachments" }
  let(:pdf) { Rails.root.join('spec/fixtures/files/sample.pdf') }
  let(:png) { Rails.root.join('spec/fixtures/files/sample.png') }

  def upload(path, content_type)
    Rack::Test::UploadedFile.new(path, content_type)
  end

  describe 'POST — envio' do
    it 'anexa e devolve título derivado do nome do arquivo, sem URL no corpo' do
      post base, params: { files: [upload(pdf, 'application/pdf')] }, headers: headers

      expect(response).to have_http_status(:created)
      anexo = JSON.parse(response.body).first
      expect(anexo['title']).to eq('sample')
      expect(anexo['format']).to eq('PDF')
      expect(anexo['is_image']).to be(false)
      expect(anexo['author_id']).to eq(autor.id)
      # **Não existe campo de URL**: ela tem prazo e é pedida no momento do
      # clique, que é quando a autorização é conferida.
      expect(anexo).not_to have_key('url')
      expect(renegotiation.reload.attachments_count).to eq(1)
    end

    # 4.20 (d) — tipo conferido pelo CONTEÚDO
    it 'rejeita .svg renomeado para .pdf pela verificação de CONTEÚDO (D-82)' do
      # No legado havia `do_not_validate_attachment_file_type` **e** o detector de
      # spoof monkey-patchado para `false`: bastava trocar a extensão.
      falso = Tempfile.new(['malicioso', '.pdf'])
      falso.write('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>')
      falso.rewind

      post base, params: { files: [Rack::Test::UploadedFile.new(falso.path, 'application/pdf')] },
                 headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(renegotiation.reload.attachments_count).to eq(0)
    end

    it 'rejeita .html renomeado para .pdf pela mesma verificação' do
      falso = Tempfile.new(['pagina', '.pdf'])
      falso.write('<!doctype html><html><body><script>alert(1)</script></body></html>')
      falso.rewind

      post base, params: { files: [Rack::Test::UploadedFile.new(falso.path, 'application/pdf')] },
                 headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # 4.21 — os limites
    it 'recusa o 5º arquivo NO SERVIDOR, com o número do catálogo' do
      4.times { post base, params: { files: [upload(pdf, 'application/pdf')] }, headers: headers }

      post base, params: { files: [upload(pdf, 'application/pdf')] }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['message']).to eq('O máximo de arquivos permitido para envio é de 4 arquivos')
      expect(renegotiation.reload.attachments_count).to eq(4)
    end

    it 'recusa arquivo de 5 MB + 1 byte' do
      grande = Tempfile.new(['grande', '.pdf'])
      grande.binmode
      grande.write(File.binread(pdf))
      grande.write("\0" * (5.megabytes + 1))
      grande.rewind

      post base, params: { files: [Rack::Test::UploadedFile.new(grande.path, 'application/pdf')] },
                 headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(renegotiation.reload.attachments_count).to eq(0)
    end

    it 'os limites vêm do CATÁLOGO — mudar a configuração muda o limite sem deploy' do
      spec_falso = Sfg::Attachments::Spec.new(
        model_key: 'renegotiation_attachment', name: :file, multiple: false,
        max_files: 1, max_size_bytes: 5.megabytes,
        content_types: %i[pdf], policy: 'project_member', variants: {}
      )
      allow(Renegotiations::AttachmentService).to receive(:spec).and_return(spec_falso)

      post base, params: { files: [upload(pdf, 'application/pdf')] }, headers: headers
      expect(response).to have_http_status(:created)

      post base, params: { files: [upload(pdf, 'application/pdf')] }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['message']).to include('1 arquivos')
    end
  end

  describe 'GET /limits' do
    it 'devolve os números do catálogo, para que a tela não tenha número escrito nela (D-50)' do
      create(:renegotiation_attachment, renegotiation: renegotiation, author: autor)

      get "#{base}/limits", headers: headers

      corpo = JSON.parse(response.body)
      expect(corpo['max_files']).to eq(4)
      expect(corpo['max_size_megabytes']).to eq(5)
      expect(corpo['used']).to eq(1)
      expect(corpo['remaining']).to eq(3)
      expect(corpo['content_types']).to include('pdf')
    end
  end

  describe 'GET — listagem (BE-225)' do
    it 'lista, busca pelo título e pagina — a rota do legado nunca funcionou' do
      # No legado o `search` montava `@limit`/`@offset` e a view iterava sobre
      # `la` quando a variável era `ra`: `NameError` garantido.
      create(:renegotiation_attachment, renegotiation: renegotiation, author: autor, title: 'Contrato')
      create(:renegotiation_attachment, renegotiation: renegotiation, author: autor, title: 'Aditivo')

      get base, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(2)
      expect(response.headers['X-Total-Count']).to eq('2')

      get base, params: { q: 'Aditivo' }, headers: headers
      expect(JSON.parse(response.body).map { |a| a['title'] }).to eq(['Aditivo'])
    end
  end

  describe 'PUT — renomear (DEC-53)' do
    it 'renomeia — no legado a action levantava NameError garantido' do
      anexo = create(:renegotiation_attachment, renegotiation: renegotiation, author: autor)

      put "#{base}/#{anexo.id}", params: { title: 'Contrato assinado 2025' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(anexo.reload.title).to eq('Contrato assinado 2025')
    end

    it 'recusa nome em branco' do
      anexo = create(:renegotiation_attachment, renegotiation: renegotiation, author: autor)
      put "#{base}/#{anexo.id}", params: { title: '   ' }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET /:id/download — 4.20 (a), (b), (c)' do
    let!(:anexo) { create(:renegotiation_attachment, renegotiation: renegotiation, author: autor) }

    # (b) Content-Disposition é SEMPRE attachment
    it 'entrega o binário com Content-Disposition: attachment e o nome original' do
      get "#{base}/#{anexo.id}/download", headers: headers

      expect(response).to have_http_status(:ok)
      # O legado usava `disposition: 'inline'` com o content-type que o UPLOADER
      # declarou — XSS armazenado na mesma origem.
      expect(response.headers['Content-Disposition']).to start_with('attachment')
      expect(response.headers['Content-Disposition']).to include('contrato.pdf')
      expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
      expect(response.body.byteslice(0, 4)).to eq('%PDF')
    end

    # (a) download SEM permissão é recusado
    it 'recusa quem NÃO participa do projeto — posse da URL não é autorização' do
      estranho = create(:user, :gerente)
      create_project_with_owner(estranho)

      get "#{base}/#{anexo.id}/download", headers: auth_headers(estranho)

      # 404, não 403: distinguir os dois transformaria o endpoint num oráculo de
      # existência de anexo.
      expect(response).to have_http_status(:not_found)
    end

    it 'recusa sem sessão nenhuma' do
      get "#{base}/#{anexo.id}/download"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'arquivo ausente responde 404 LEGÍVEL, não 500' do
      anexo.file.purge
      get "#{base}/#{anexo.id}/download", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)['message']).to include('não está disponível')
    end

    # (c) o arquivo NÃO é alcançável por caminho direto em public/
    it 'o binário não existe em public/ — nem em `public/system`, nem em `public/uploads`' do
      # É o coração do D-82: no legado o path era
      # `:rails_root/public/system/:attachment/:id/:basename.:extension`, servido
      # como estático e sem autenticação nenhuma.
      expect(Dir.glob(Rails.root.join('public/system/**/*')).select { |f| File.file?(f) }).to be_empty
      expect(Dir.glob(Rails.root.join('public/uploads/**/*.pdf'))).to be_empty
      # E o serviço de armazenamento não aponta para `public/`.
      caminho = ActiveStorage::Blob.service.send(:path_for, anexo.file.blob.key)
      expect(caminho.to_s).not_to include("#{Rails.root}/public")
    end
  end

  describe 'DELETE — 4.20 (e): só o autor' do
    it 'o autor remove, e o contador cai' do
      anexo = create(:renegotiation_attachment, renegotiation: renegotiation, author: autor)

      delete "#{base}/#{anexo.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(renegotiation.reload.attachments_count).to eq(0)
    end

    it 'OUTRO participante do projeto NÃO remove — checado no servidor (BE-229)' do
      # No legado a regra de dono era **só visual**: bastava chamar a rota.
      outro = create(:user, :colaborador)
      Membership.create!(project: project, user: outro, role: 'participante')
      anexo = create(:renegotiation_attachment, renegotiation: renegotiation, author: autor)

      delete "#{base}/#{anexo.id}", headers: auth_headers(outro, project: project)

      expect(response).to have_http_status(:forbidden)
      expect(RenegotiationAttachment.exists?(anexo.id)).to be(true)
    end

    it 'registro SEM arquivo é removido normalmente' do
      anexo = create(:renegotiation_attachment, renegotiation: renegotiation, author: autor)
      anexo.file.purge

      delete "#{base}/#{anexo.id}", headers: headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'a política de leitura do motor (OPS-192)' do
    it 'só quem participa do projeto lê o binário pelo endpoint de URL assinada' do
      anexo = create(:renegotiation_attachment, renegotiation: renegotiation, author: autor)
      signed = Sfg::Attachments.sign_id(anexo.file.attachment.id)

      get "/api/v1/attachments/#{signed}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['url']).to be_present

      estranho = create(:user, :gerente)
      create_project_with_owner(estranho)
      get "/api/v1/attachments/#{signed}", headers: auth_headers(estranho)
      expect(response).to have_http_status(:not_found)
    end

    it 'gera miniatura de VARIANTE para imagem, não o arquivo original (FE-208)' do
      anexo = build(:renegotiation_attachment, renegotiation: renegotiation, author: autor)
      anexo.file.attach(io: File.open(png), filename: 'foto.png', content_type: 'image/png')
      anexo.save!
      signed = Sfg::Attachments.sign_id(anexo.file.attachment.id)

      get "/api/v1/attachments/#{signed}/variant", params: { variant: 'thumb' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['url']).to be_present
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

# S13 — motor único de anexos (sub-bloco B, antecipado pela DEC-63).
#
# O que estes exemplos travam é o que o legado NÃO fazia: os limites de anexo
# viviam só no JavaScript da tela (`SFG::Metadata::MAX_FILES_PER_RENEGOTIATION`,
# `MAX_FILE_SIZE` interpolados num `.js.erb`) e o servidor aceitava qualquer coisa.
RSpec.describe Attachable do
  let(:png) { Rails.root.join('spec/fixtures/files/sample.png') }
  let(:fake_png) { Rails.root.join('spec/fixtures/files/fake.png') }

  def attach(record, name, path, content_type: 'image/png', filename: nil)
    record.public_send(name).attach(
      io: File.open(path),
      filename: filename || File.basename(path),
      content_type: content_type
    )
    record
  end

  describe 'declaração' do
    it 'recusa anexo que não está no catálogo CFG-02' do
      klass = Class.new(ApplicationRecord) do
        self.table_name = 'projects'
        def self.name = 'Project'
        include Attachable
      end

      expect { klass.sfg_attachment(:inexistente) }
        .to raise_error(KeyError, /config\/attachments\.yml/)
    end

    it 'expõe o spec declarado, com os números vindos do catálogo' do
      spec = User.sfg_attachment_specs[:avatar]
      expect(spec.max_size_bytes).to eq(3.megabytes)
      expect(spec.multiple?).to be(false)
      expect(spec.variant_names).to include(:thumb, :preview, :large)
    end
  end

  describe 'validação de tamanho (NO SERVIDOR)' do
    it 'aceita imagem dentro do limite' do
      user = attach(create(:user), :avatar, png)
      expect(user).to be_valid
    end

    it 'recusa arquivo acima do limite declarado, com o número do catálogo na mensagem' do
      user = create(:user)
      oversized = StringIO.new(File.binread(png) + ("\0" * 4.megabytes))
      user.avatar.attach(io: oversized, filename: 'grande.png', content_type: 'image/png')

      expect(user).not_to be_valid
      expect(user.errors.full_messages.join)
        .to include('O tamanho máximo de cada arquivo permitido para envio é de 3 MB')
    end
  end

  describe 'validação por conteúdo real (magic bytes) — OPS-623' do
    # Este é o exemplo que separa o motor novo do `api/v1/uploads.rb:31` da base,
    # que confia no `Content-Type` que o cliente declarou (flag F-09).
    #
    # Ele também é a rede da opção `spoofing_protection: true` no `Attachable`:
    # SEM ela, este mesmo arquivo passava (conferido). A opção é fácil de perder
    # numa refatoração, e a validação continua "existindo" — só que decorativa.
    it 'recusa arquivo cujo Content-Type declarado mente sobre o conteúdo' do
      user = attach(create(:user), :avatar, fake_png, content_type: 'image/png')

      expect(user).not_to be_valid
      expect(user.errors[:avatar].join).to include('formato')
    end
  end

  describe 'derivados' do
    it 'gera a variante nomeada com o tamanho do legado, sem ampliar a imagem' do
      user = attach(create(:user), :avatar, png)
      user.save!

      variant = user.avatar.variant(:thumb).processed
      expect(variant.image.blob).to be_present
      # O derivado do avatar sai em JPEG, como no legado (`:thumb => ['80>', :jpg]`).
      expect(variant.image.blob.content_type).to eq('image/jpeg')

      # `resize_to_limit` equivale ao `'80>'` do Paperclip: **só reduz**. A imagem
      # de 4px continua com 4px — se um dia alguém trocar por `resize_to_fill`,
      # este exemplo reprova.
      processed = Vips::Image.new_from_buffer(variant.image.blob.download, '')
      expect(processed.width).to eq(4)
    end
  end

  describe 'payload para a entity' do
    it 'devolve signed_id, nunca o id cru da linha de active_storage_attachments' do
      user = attach(create(:user), :avatar, png)
      user.save!

      payload = user.sfg_attachment_payload(:avatar)
      expect(payload[:filename]).to eq('sample.png')
      expect(payload[:id]).to be_a(String)
      expect(payload[:id]).not_to eq(user.avatar.attachment.id.to_s)
      expect(Sfg::Attachments.find_signed(payload[:id])).to eq(user.avatar.attachment)
    end
  end
end

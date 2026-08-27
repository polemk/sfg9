# frozen_string_literal: true

require 'rails_helper'

# S13 / OPS-495 + FE-484, agora **sobre o domínio real** (S9) — o teto de
# **quantidade** e de **tamanho** do anexo de renegociação, validado NO SERVIDOR.
#
# Por que este arquivo existe: os dois números
# (`SFG::Metadata::MAX_FILES_PER_RENEGOTIATION = 4`, `MAX_FILE_SIZE = 5.megabytes`)
# no legado só existiam interpolados no JavaScript da tela
# (`renegotiations/detail/tabs/_tab_geral.js.erb:90-102`). O servidor aceitava
# qualquer quantidade e qualquer tamanho — bastava um `curl`.
#
# ## O que mudou quando a S9 chegou, e por quê
#
# A S13 escreveu este arquivo **antes** de o domínio existir, montando um
# `Renegotiation` de mentira sobre a tabela `projects` e um `has_many_attached
# :files`. O próprio cabeçalho dizia: *"quando a S9 entregar o model de verdade, o
# `if` abaixo passa a usá-lo sozinho e este andaime some"*. O andaime sumiu — e o
# desenho ficou diferente do que aquele rascunho supunha:
#
# **cada arquivo é uma LINHA de `renegotiation_attachments`**, com um binário só,
# porque a linha precisa carregar `title` (o usuário renomeia — DEC-53) e
# `user_id` (só o autor exclui — BE-229). Nenhum dos dois cabe num blob. A chave
# do catálogo é `renegotiation_attachment.file`, e o teto de 4 é contado em
# **linhas irmãs** por `Renegotiations::AttachmentService`, lendo o número do
# mesmo `config/attachments.yml`.
#
# **As garantias sob teste são exatamente as mesmas.** O que mudou foi a camada
# onde elas são aplicadas — e é por isso que este arquivo continua existindo em
# vez de ser apagado.
RSpec.describe 'Anexo de renegociação — os limites, no servidor' do
  let(:pdf) { Rails.root.join('spec/fixtures/files/sample.pdf') }
  let(:png) { Rails.root.join('spec/fixtures/files/sample.png') }
  let(:autor) { create(:user) }
  let(:renegotiation) { create(:renegotiation) }

  def upload(path, content_type)
    { filename: File.basename(path), type: content_type, tempfile: File.open(path) }
  end

  def anexar(arquivos)
    Renegotiations::AttachmentService.attach!(
      renegotiation: renegotiation, files: Array(arquivos), actor: autor
    )
  end

  it 'aceita até 4 arquivos' do
    resultado = anexar(Array.new(4) { upload(pdf, 'application/pdf') })

    expect(resultado[:status]).to eq(201)
    expect(renegotiation.reload.attachments_count).to eq(4)
  end

  it 'recusa o quinto arquivo com o texto do legado e o número do catálogo' do
    anexar(Array.new(4) { upload(pdf, 'application/pdf') })

    resultado = anexar([upload(pdf, 'application/pdf')])

    expect(resultado[:status]).to eq(422)
    expect(resultado[:error]).to eq('O máximo de arquivos permitido para envio é de 4 arquivos')
    expect(renegotiation.reload.attachments_count).to eq(4)
  end

  it 'conta o que JÁ está anexado, não só o lote que chegou' do
    # Quatro requisições de um arquivo cada passariam por qualquer validação que
    # olhasse apenas o lote. É por isso que a contagem é feita contra o estado.
    4.times { anexar([upload(pdf, 'application/pdf')]) }

    expect(anexar([upload(pdf, 'application/pdf')])[:status]).to eq(422)
  end

  it 'recusa arquivo acima de 5 MB mesmo com o cliente adulterado' do
    grande = Tempfile.new(['grande', '.pdf'])
    grande.binmode
    grande.write(File.binread(pdf))
    grande.write("\0" * 6.megabytes)
    grande.rewind

    resultado = anexar([{ filename: 'grande.pdf', type: 'application/pdf', tempfile: grande }])

    expect(resultado[:status]).to eq(422)
    expect(resultado[:error]).to include('O tamanho máximo de cada arquivo permitido para envio é de 5 MB')
    expect(renegotiation.reload.attachments_count).to eq(0)
  end

  it 'aceita imagem junto de documento — o anexo de renegociação não é só PDF' do
    resultado = anexar([upload(pdf, 'application/pdf'), upload(png, 'image/png')])

    expect(resultado[:status]).to eq(201)
    expect(renegotiation.reload.attachments_count).to eq(2)
  end

  it 'o lote é tudo ou nada: um arquivo grande no meio não deixa metade gravada' do
    grande = Tempfile.new(['grande', '.pdf'])
    grande.binmode
    grande.write(File.binread(pdf))
    grande.write("\0" * 6.megabytes)
    grande.rewind

    resultado = anexar([upload(pdf, 'application/pdf'),
                        { filename: 'grande.pdf', type: 'application/pdf', tempfile: grande }])

    expect(resultado[:status]).to eq(422)
    # No legado o controller iterava criando um registro por arquivo, acumulava os
    # erros num `ActiveModel::Errors` avulso e respondia 422 **com metade dos
    # arquivos já gravados**.
    expect(renegotiation.reload.attachments_count).to eq(0)
  end

  it 'a contagem do registro acompanha a remoção' do
    anexar(Array.new(2) { upload(pdf, 'application/pdf') })
    anexo = renegotiation.attachments.reload.first

    Renegotiations::AttachmentService.destroy!(attachment: anexo, actor: autor)

    expect(renegotiation.reload.attachments_count).to eq(1)
  end
end

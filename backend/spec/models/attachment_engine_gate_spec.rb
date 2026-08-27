# frozen_string_literal: true

require 'rails_helper'

# S13 — **portão do motor único de anexos** (C-04, D-82, DEC-91).
#
# Este arquivo existe porque o defeito que ele impede já aconteceu **duas vezes**
# nesta base, e as duas silenciosamente:
#
#  1. A base ai9 pós-trim tinha DOIS caminhos de arquivo: ActiveStorage em `Medium`
#     e gravação crua em `public/uploads` servida sem autenticação pelo
#     `AssetsProxyController` (C-04 / flag F-10).
#  2. Enquanto o motor era construído, uma fatia paralela declarou
#     `has_one_attached :logo` à mão no `Carrier`, com limite diferente do legado
#     (2 MB em vez de 1 MB) e com a proteção contra spoof **desligada** — apesar de
#     o comentário do próprio código afirmar que ela estava ligada. Ninguém agiu de
#     má-fé: declarar anexo à mão é o caminho óbvio, e nada reprovava.
#
# Foi por isso que o motor foi ANTECIPADO (DEC-63/P-100), antes da S9 e dos seus 4
# anexos de documento financeiro. Este portão é o que faz a antecipação valer para o
# resto da migração: **anexo novo passa por `config/attachments.yml`, ou reprova.**
RSpec.describe 'Motor único de anexos' do
  MODEL_FILES = Dir[Rails.root.join('app/models/*.rb')].sort

  # A lista de exceções está **vazia de propósito**, e é assim que deve ficar.
  #
  # Ela existia por causa do `medium.rb`, model da base ai9 que o Safegold nunca usou
  # (`media` não tinha dono nem escopo, e `media_type` só aceitava `image`/`video` —
  # anexo de renegociação é DOCUMENTO, C-13/D-O). A **DEC-113 removeu o `Medium`**
  # junto com a galeria, seu único consumidor, então a exceção deixou de ter alvo.
  #
  # Manter a chave apontando para um arquivo inexistente seria pior que inútil: no dia
  # em que alguém criasse um `medium.rb` novo, ele nasceria **isento do portão** sem
  # que ninguém tivesse decidido isso. Exceção órfã é permissão esquecida.
  FORA_DO_MOTOR = {}.freeze

  it 'nenhum model do Safegold declara anexo fora do `Attachable`' do
    infratores = MODEL_FILES.filter_map do |path|
      nome = File.basename(path)
      next if FORA_DO_MOTOR.key?(nome)

      fonte = File.read(path)
      next unless fonte.match?(/^\s*has_(one|many)_attached\b/)
      next if fonte.match?(/^\s*sfg_attachment\b/)

      nome
    end

    expect(infratores).to be_empty,
                          "Models com anexo declarado à mão: #{infratores.join(', ')}. " \
                          'Use `include Attachable` + `sfg_attachment :nome`, com o limite em ' \
                          'config/attachments.yml (CFG-02). Anexo com limite escrito no model é ' \
                          'o segundo motor nascendo.'
  end

  it 'todo anexo declarado tem entrada no catálogo, com política de leitura' do
    # `spec_for` levanta quando falta a entrada ou quando a política é desconhecida.
    expect { Sfg::Attachments.all_specs }.not_to raise_error

    Sfg::Attachments.all_specs.each do |spec|
      expect(spec.max_size_bytes).to be_positive, "#{spec.model_key}.#{spec.name} sem limite de tamanho"
      expect(spec.content_types).not_to be_empty, "#{spec.model_key}.#{spec.name} sem allowlist de tipo"
      expect(Sfg::Attachments::POLICIES).to have_key(spec.policy)
    end
  end

  it 'nenhum model do Safegold escreve arquivo em `public/uploads`' do
    # É o segundo caminho da base (C-04): arquivo servido como estático, sem
    # autenticação — o D-82 do legado por outro nome.
    # Só linhas de CÓDIGO: comentário que EXPLICA por que o caminho antigo foi
    # abandonado é documentação, não reincidência.
    infratores = (MODEL_FILES + Dir[Rails.root.join('app/services/**/*.rb')]).select do |path|
      File.readlines(path).any? { |linha| linha.include?('public/uploads') && !linha.strip.start_with?('#') }
    end

    expect(infratores.map { |p| File.basename(p) }).to be_empty
  end

  it 'os limites do anexo de renegociação são os do legado, e vêm do catálogo' do
    # ⚠ A chave é `renegotiation_attachment.file`, não `renegotiation.files`.
    # Quando a S9 chegou, o anexo virou uma LINHA por arquivo — a linha carrega
    # `title` (o usuário renomeia, DEC-53) e `user_id` (só o autor exclui,
    # BE-229), e nenhum dos dois cabe num blob. Ver a nota no catálogo.
    spec = Sfg::Attachments.spec_for('renegotiation_attachment', 'file')

    # `SFG::Metadata::MAX_FILES_PER_RENEGOTIATION = 4` e `MAX_FILE_SIZE = 5.megabytes`.
    # A S9 herda estes números prontos e validados no servidor — no legado eles só
    # existiam interpolados no JavaScript da tela.
    #
    # `max_files` continua aqui **apesar de `multiple?` ser falso**: é o teto por
    # RENEGOCIAÇÃO, contado em linhas irmãs pelo `Renegotiations::AttachmentService`.
    # O número continua num lugar só.
    expect(spec.max_files).to eq(4)
    expect(spec.max_size_bytes).to eq(5.megabytes)
    expect(spec.multiple?).to be(false)
    expect(spec.policy).to eq('project_member')
    expect(spec.content_types).to include(:pdf)
  end

  it 'o limite do logo do portador é o do legado (1 MB), não um número novo' do
    expect(Sfg::Attachments.spec_for('carrier', 'logo').max_size_bytes).to eq(1.megabyte)
  end
end

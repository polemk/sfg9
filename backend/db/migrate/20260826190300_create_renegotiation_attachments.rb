# frozen_string_literal: true

# S9 / DB-193, DB-195, DB-571 — **anexos da renegociação**.
#
# É o anexo que motivou a antecipação do motor único (DEC-63/P-100) e o que o
# **D-82** descreve inteiro. No legado:
#
#   - o binário ficava em `public/system/:attachment/:id/:basename.:extension`,
#     servido como **estático**, com URL adivinhável e **sem autenticação**;
#   - o download respondia `disposition: 'inline'` com o content-type que o
#     **uploader** declarou — XSS armazenado na mesma origem;
#   - a validação de tipo estava **desligada** (`do_not_validate_attachment_file_type`)
#     e o detector de spoof estava monkey-patchado para `false`;
#   - a regra de "só o autor exclui" era **só visual**;
#   - os limites (4 arquivos, 5 MB) existiam **só no JavaScript da tela**, lendo um
#     seletor `.lesson_attachment_content_wrapper` — de OUTRO produto — e comparando
#     com `NaN` (**D-50**).
#
# Nada disso é portado. O binário vai para o **motor único** (`Attachable` +
# `config/attachments.yml`, chave `renegotiation_attachment.file`), que autoriza
# antes de assinar a URL, confere o tipo pelos **magic bytes** e aplica os limites
# **no servidor**. As 4 colunas do Paperclip (`file_file_name`,
# `file_content_type`, `file_file_size`, `file_updated_at`) **não** são recriadas —
# o ETL da S14 copia o binário e reanexa (bloqueado pelo DEC-84 até a cópia de
# `public/system/` chegar).
#
# **Por que uma TABELA e não `has_many_attached :files` no `Renegotiation`:** a
# linha carrega dois dados que o blob não tem e que a regra precisa — **`title`**,
# que o usuário edita (DEC-53 manda consertar o "renomear anexo", que no legado
# levantava `NameError` garantido), e **`user_id`**, o autor, que é quem pode
# excluir (BE-229, checado no servidor). É também o que a S14 já declara em
# `Sfg::Etl::Attachments::MAP` e o que dá sentido ao contador `attachments_count`.
# O teto de **4 arquivos por renegociação** é contado em linhas irmãs pelo
# `Renegotiations::AttachmentService`, lendo o número do catálogo — nunca do código.
class CreateRenegotiationAttachments < ActiveRecord::Migration[8.0]
  def change
    create_table :renegotiation_attachments, id: :uuid, default: -> { 'gen_random_uuid()' },
                                             comment: 'Anexo (documento financeiro) de uma renegociação. ' \
                                                      'Binário no ActiveStorage privado — nunca em `public/`.' do |t|
      t.uuid :renegotiation_id, null: false, comment: 'Renegociação dona.'
      t.uuid :project_id, null: false, comment: 'Projeto, denormalizado e coerente por FK composta (C1).'
      t.uuid :user_id, comment: 'AUTOR do envio, vindo da sessão. É quem — e só quem — pode excluir (BE-229).'

      t.string :title, null: false,
                       comment: 'Nome exibido. Nasce do nome do arquivo sem a extensão e é EDITÁVEL (DEC-53).'

      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    add_index :renegotiation_attachments, :renegotiation_id, name: 'index_reneg_attachments_on_renegotiation'
    add_index :renegotiation_attachments, :project_id, name: 'index_reneg_attachments_on_project'
    add_index :renegotiation_attachments, :user_id, name: 'index_reneg_attachments_on_user'
    add_index :renegotiation_attachments, %i[renegotiation_id created_at],
              name: 'index_reneg_attachments_ordering'
    add_index :renegotiation_attachments, :legacy_id, unique: true, name: 'index_reneg_attachments_on_legacy_id'

    add_foreign_key :renegotiation_attachments, :users, column: :user_id, on_delete: :nullify
    add_foreign_key :renegotiation_attachments, :projects, column: :project_id
    add_foreign_key :renegotiation_attachments, :renegotiations,
                    column: %i[renegotiation_id project_id],
                    primary_key: %i[id project_id],
                    name: 'fk_reneg_attachments_renegotiation_project'
  end
end

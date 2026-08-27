# frozen_string_literal: true

# S1 / F.3 — `user_profiles`, 1:1 com `users`. Fecha DB-541.
#
# `livetat_auth_user_infos` do legado tinha 41 campos, dos quais 12 já existiam em
# `users` na base ai9 e 10 entraram lá pela migration anterior (identidade e perfil de
# uso diário). O que sobra é cadastro secundário — telefone decomposto em país/DDD/
# número, contato de emergência, dados de endereço adicional — e não pertence a `users`:
#
#  1. `users` é **base compartilhada** (Princípio 6b). Cada coluna acrescentada ali é
#     uma coluna que os outros sistemas da base carregam sem usar.
#  2. O caminho quente do produto é login e listagem de contas, e nenhum dos dois lê
#     estes campos. Mantê-los fora de `users` mantém a linha do caminho quente curta.
#
# **O telefone decomposto NÃO substitui `users.phone`.** `users.phone` é o canal de
# login (DEC-14) e continua sendo a verdade para envio de código; país/DDD/número aqui
# são o que o formulário de cadastro do legado coletava, preservados para exibição e
# para o dry-run do ETL.
class CreateUserProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :user_profiles, id: :uuid, comment: 'Cadastro secundário 1:1 com `users` (F.3 / DB-541). Substitui `livetat_auth_user_infos`.' do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true, index: { unique: true },
                          comment: 'Dono do perfil. Índice ÚNICO: 1:1, não 1:N.'

      t.string :phone_country_code, comment: 'DDI do telefone principal, como o formulário do legado coletava.'
      t.string :phone_area_code,    comment: 'DDD do telefone principal.'
      t.string :phone_number,       comment: 'Número do telefone principal, sem DDI/DDD.'

      t.string :secondary_phone_country_code, comment: 'DDI do segundo telefone. O legado tinha 2 telefones.'
      t.string :secondary_phone_area_code,    comment: 'DDD do segundo telefone.'
      t.string :secondary_phone_number,       comment: 'Número do segundo telefone.'

      t.string :emergency_contact_name,  comment: 'Contato de emergência — nome.'
      t.string :emergency_contact_phone, comment: 'Contato de emergência — telefone.'

      t.string :company_name, comment: 'Empresa declarada pelo usuário. Descritivo, não é vínculo.'
      t.string :occupation,   comment: 'Cargo/ocupação declarada.'
      t.string :nationality,  comment: 'Nacionalidade declarada.'
      t.string :marital_status, comment: 'Estado civil declarado.'

      t.timestamps
    end
  end
end

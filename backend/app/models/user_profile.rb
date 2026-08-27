# frozen_string_literal: true

# Cadastro secundário 1:1 com `User` (F.3 / DB-541).
#
# Substitui `livetat_auth_user_infos` do legado sem virar tabela-espelho: o que o
# produto usa todo dia mora em `users`; o que só o cadastro coleta mora aqui.
#
# **Nada aqui é canal de login.** `phone_country_code`/`phone_area_code`/`phone_number`
# são o telefone decomposto como o formulário do legado o coletava — quem manda o
# código de acesso é `users.phone` (DEC-14).
class UserProfile < ApplicationRecord
  belongs_to :user

  validates :user_id, uniqueness: true

  # O telefone remontado, para exibição. Devolve `nil` quando não há número — nunca
  # uma string com o DDI solto, que na tela parece um telefone truncado.
  def full_phone
    return nil if phone_number.blank?

    [phone_country_code, phone_area_code, phone_number].compact_blank.join
  end

  def full_secondary_phone
    return nil if secondary_phone_number.blank?

    [secondary_phone_country_code, secondary_phone_area_code, secondary_phone_number].compact_blank.join
  end
end

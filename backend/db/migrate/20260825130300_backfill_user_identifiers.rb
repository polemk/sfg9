# frozen_string_literal: true

# BE-048 — preenche `users.identifier` para quem já existia antes da coluna.
#
# O `before_create` do model só serve registro novo. Sem este backfill, toda conta
# anterior a 25/08/2026 fica sem código curto — e a tela de contas mostraria a etiqueta
# só para os cadastros novos, o que na prática é pior que não ter a etiqueta: sugere que
# só algumas contas têm código.
#
# O sorteio é o mesmo do model, com retry contra o índice único. Registro a registro de
# propósito: a base de usuários é pequena e um `UPDATE` em lote com valor aleatório por
# linha não tem como detectar colisão antes de gravar.
class BackfillUserIdentifiers < ActiveRecord::Migration[8.0]
  ALPHABET = ('A'..'Z').to_a.concat(('0'..'9').to_a).freeze

  def up
    say_with_time 'preenchendo users.identifier' do
      taken = select_values('SELECT identifier FROM users WHERE identifier IS NOT NULL').to_set
      ids = select_values('SELECT id FROM users WHERE identifier IS NULL')

      ids.each do |id|
        candidate = nil
        10.times do
          try = Array.new(6) { ALPHABET.sample(random: SecureRandom) }.join
          next if taken.include?(try)

          candidate = try
          break
        end
        next if candidate.nil?

        taken << candidate
        execute(ActiveRecord::Base.sanitize_sql_array(
                  ['UPDATE users SET identifier = ? WHERE id = ?::uuid', candidate, id]
                ))
      end
      ids.size
    end
  end

  # Irreversível por escolha: desfazer apagaria códigos que os usuários já podem ter
  # anotado. A coluna inteira sai com o `down` da migration que a criou.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end

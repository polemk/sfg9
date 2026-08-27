# frozen_string_literal: true

# S1 / **DEC-108** — as 7 abilities com efeito real voltam, e passam a ser
# checadas NO SERVIDOR.
#
# ## O que esta migration conserta
#
# O catálogo tinha **uma** linha (`user_is_readonly`) contra as 17 do legado. O
# corte estava apoiado numa afirmação **falsa** — "nenhuma é consultada em lugar
# nenhum do app". A contagem de call sites reais (excluindo
# `ability_factory_decorator.rb` e os seeds) desmente:
#
#   | ability                     | call sites |
#   | --------------------------- | ---------: |
#   | `user_is_readonly`          |        115 |
#   | `may_create_users`          |          5 |
#   | `max_users_amount`          |          3 |
#   | `max_invitations_amount`    |          2 |
#   | `may_invite_users`          |          1 |
#   | `may_delete_users`          |          1 |
#   | `may_modify_public_entries` |          1 |
#   | as outras 10                |      **0** |
#
# O "zero" valia para 10 delas, não para 16. As 10 continuam fora (agora com a
# justificativa certa, verificada uma a uma); as **7** voltam.
#
# ## Por que o catálogo precisa de tipo e de valor numérico
#
# Duas das sete (`max_users_amount`, `max_invitations_amount`) são **limite**,
# não booleano: o legado as declara com `type: AbilityFactory.limit` e valor
# inteiro (`ability_factory.rb:73-74`). Um `granted` booleano não guarda "50".
# Daí `permissions.kind` + `default_limit_value` no catálogo e `limit_value` nas
# duas tabelas de concessão — mesma forma da resolução que já existe
# (papel primeiro, override do usuário por cima).
#
# `NULL` em `limit_value` significa **sem limite**, e é diferente de `0`, que
# significa **nenhum permitido** (é o valor que o legado dá ao Gerente e ao
# Colaborador em `max_users_amount`, `db/seeds.rb:79,94`).
#
# ## `login_codes.invited_by_id`
#
# `max_invitations_amount` só pode ser aplicado se der para **contar** convites
# em aberto de quem convida. No ai9 o convite é um `LoginCode` emitido por
# `Auth::InviteService`, e a tabela não guardava quem o emitiu. Coluna nula,
# índice parcial, preenchida só pelo caminho de convite — nenhum outro emissor
# de `LoginCode` muda de comportamento.
class AsSeteAbilitiesComEfeitoRealVoltam < ActiveRecord::Migration[8.0]
  def change
    add_column :permissions, :kind, :string, null: false, default: 'conditional',
               comment: '`conditional` (booleano) ou `limit` (teto numérico). O legado já distinguia os dois ' \
                        'tipos em `AbilityFactory` — o catálogo do ai9 passou a distinguir também (DEC-108).'
    add_column :permissions, :default_limit_value, :integer,
               comment: 'Teto usado quando nem o papel nem o usuário declaram um. NULL = sem limite.'

    add_column :user_type_permissions, :limit_value, :integer,
               comment: 'Teto do PAPEL para uma permissão `limit`. NULL = sem limite; 0 = nenhum permitido.'
    add_column :user_permissions, :limit_value, :integer,
               comment: 'Teto do USUÁRIO, sobrepõe o do papel. NULL = sem override de teto.'

    add_column :login_codes, :invited_by_id, :uuid,
               comment: 'Quem emitiu o convite (DEC-108). Só o caminho de convite preenche; login normal deixa NULL.'
    add_index :login_codes, :invited_by_id, where: 'invited_by_id IS NOT NULL',
                                            name: 'idx_login_codes_invited_by'
  end
end

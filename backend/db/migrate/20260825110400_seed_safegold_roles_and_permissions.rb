# frozen_string_literal: true

# S0 / DB-005, DB-006, DB-008, DB-501, DB-502, DB-730 — o contrato C3 no banco.
#
# **DEC-41, parte 1.** Os PAPÉIS são os do legado Safegold; a NUMERAÇÃO é a
# convenção do ai9 — **menor = mais poder**, que é como `UserType.higher_than`
# (`where('hierarchy_level < ?', level)`) já compara. Nada em `user_type.rb` é
# invertido.
#
#   | Papel       | ai9 | legado |
#   | OG          |  1  |  1111  |
#   | Admin       |  2  |   998  |
#   | Gerente     |  3  |   888  |
#   | Colaborador |  4  |   799  |
#
# **DEC-41, parte 2.** `client`, `free` e `visitor` são REMOVIDOS. Só OG
# sobrevive do seed da base ai9. Com `client` e `free` fora, nada disputa os
# níveis 2 e 4 — que é a colisão que originou a pergunta P-061.
#
# Usuário que apontava para um tipo removido vira **Colaborador** (DEC-18.8: o
# papel vazio é tratado como Colaborador e sai numa lista de exceções, nunca
# promovido nem bloqueado em silêncio). O `SELECT` de conferência abaixo é
# impresso no log da migration exatamente para produzir essa lista.
#
# SQL cru de propósito: migration que chama model quebra quando o model muda.
class SeedSafegoldRolesAndPermissions < ActiveRecord::Migration[8.0]
  # Níveis temporários fora da faixa útil, só para liberar 2 e 4 antes do insert
  # (`user_types.hierarchy_level` é único).
  PARKING = { 'client' => 9002, 'free' => 9004, 'visitor' => 9005 }.freeze

  SAFEGOLD_ROLES = [
    ['admin',       2, 'Administrador do cliente — todos os recursos, limitado por hierarquia inferior'],
    ['gerente',     3, 'Gestor operacional — cadastro e projetos; não alcança Permissões nem o grupo Admin'],
    ['colaborador', 4, 'Usuário final por projeto — leitura dos catálogos globais e operação dos projetos em que participa']
  ].freeze

  def up
    say_with_time 'DEC-41: estacionando client/free/visitor fora dos níveis 2 e 4' do
      PARKING.each do |name, level|
        execute <<~SQL.squish
          UPDATE user_types SET hierarchy_level = #{level}, updated_at = NOW()
          WHERE LOWER(name) = '#{name}'
        SQL
      end
    end

    say_with_time 'DEC-41: inserindo Admin(2), Gerente(3), Colaborador(4)' do
      SAFEGOLD_ROLES.each do |name, level, description|
        execute <<~SQL.squish
          INSERT INTO user_types (id, name, description, hierarchy_level, created_at, updated_at)
          VALUES (gen_random_uuid(), '#{name}', '#{description}', #{level}, NOW(), NOW())
          ON CONFLICT (name) DO UPDATE
            SET hierarchy_level = EXCLUDED.hierarchy_level,
                description     = EXCLUDED.description,
                updated_at      = NOW()
        SQL
      end
    end

    # Lista de exceções (DEC-18.8): quem perdeu o papel aparece no log.
    orphans = select_all(<<~SQL.squish)
      SELECT u.id, u.email, u.phone, t.name AS old_type
      FROM users u JOIN user_types t ON t.id = u.user_type_id
      WHERE LOWER(t.name) IN ('client', 'free', 'visitor')
    SQL
    orphans.each do |row|
      say "EXCEÇÃO DEC-18.8: #{row['email'] || row['phone']} era `#{row['old_type']}` → vira `colaborador`", true
    end

    say_with_time 'DEC-41: reatribuindo usuários dos tipos removidos para colaborador' do
      execute <<~SQL.squish
        UPDATE users SET user_type_id = (SELECT id FROM user_types WHERE name = 'colaborador'),
                         updated_at   = NOW()
        WHERE user_type_id IN (SELECT id FROM user_types WHERE LOWER(name) IN ('client', 'free', 'visitor'))
      SQL
    end

    say_with_time 'DEC-41: removendo client/free/visitor' do
      execute "DELETE FROM user_types WHERE LOWER(name) IN ('client', 'free', 'visitor')"
    end

    # DB-008 / BE-505 / OPS-009 — o PRIMEIRO seed de `permissions` da base ai9.
    # Das 17 abilities do legado esta é a única que sobrevive (DEC-18.6): deixa
    # de ser flag de view e vira checagem de servidor (`require_not_readonly!`).
    say_with_time 'DEC-18.6: catálogo de permissions com user_is_readonly' do
      execute <<~SQL.squish
        INSERT INTO permissions (key, title, description, is_active, sort_order, created_at, updated_at)
        VALUES (
          'user_is_readonly',
          'Somente leitura',
          'Nega todo verbo de escrita (POST/PUT/PATCH/DELETE) ao usuário. Única das 17 abilities do legado que sobrevive (DEC-18.6). Exceção: o aceite dos Termos pelo próprio usuário nunca é bloqueado (DC-09).',
          true, 10, NOW(), NOW()
        )
        ON CONFLICT (key) DO NOTHING
      SQL
    end
  end

  def down
    execute "DELETE FROM permissions WHERE key = 'user_is_readonly'"
    execute "DELETE FROM user_types WHERE LOWER(name) IN ('admin', 'gerente', 'colaborador')"
    PARKING.each_key do |name|
      execute <<~SQL.squish
        INSERT INTO user_types (id, name, description, hierarchy_level, created_at, updated_at)
        VALUES (gen_random_uuid(), '#{name}', 'restaurado pelo rollback', #{PARKING[name] - 9000}, NOW(), NOW())
        ON CONFLICT (name) DO NOTHING
      SQL
    end
  end
end

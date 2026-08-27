# frozen_string_literal: true

class AddFreeUserType < ActiveRecord::Migration[7.1]
  def up
    execute <<-SQL
      INSERT INTO user_types (id, name, description, hierarchy_level, created_at, updated_at)
      VALUES (gen_random_uuid(), 'free', 'Free - Acesso restrito ao perfil', 10, NOW(), NOW());
    SQL
  end

  def down
    execute <<-SQL
      DELETE FROM user_types WHERE name = 'free';
    SQL
  end
end

# frozen_string_literal: true

# S1 — as colunas de identidade e de bloqueio que o Safegold traz do legado `sfg`.
#
# Fecha DB-002, DB-540, BE-048 e o ramo de identificação alternativa da DEC-45.
#
# Cada bloco abaixo existe por um motivo concreto:
#
#  - **`blocked_at` (DEC-39 / DB-002).** No legado havia DOIS campos concorrentes,
#    `is_active` e `deactivated`, e `users.is_active` (criada em 2021) **não tinha um
#    único leitor** — nenhum `active_for_authentication?`, nenhum filtro de controller.
#    "Replicar" ali significaria não bloquear ninguém, e toda conta desligada no Django
#    anterior entraria no produto novo com acesso pleno. Os dois colapsam em UM campo,
#    que o gate central lê de verdade. Conta com `is_active = 0` no ETL nasce com
#    `blocked_at` preenchido e sai na lista de exceções para revisão humana.
#
#  - **`username` (DEC-45).** No legado `devise.rb:14` define
#    `authentication_keys = [:login]` e a resolução era
#    `lower(username) = :value OR lower(email) = :value`. Sem portar isto, quem só sabe
#    o próprio usuário perde acesso no dia 1 do cutover.
#    A coluna é **nullable** e o índice é **único parcial**
#    (`WHERE username IS NOT NULL`) porque `users` é base compartilhada com outros
#    sistemas (Princípio 6b): a terceira chave de identidade não pode impor nada a quem
#    não a usa. E `username` **identifica, não recebe**: e-mail e telefone continuam
#    sendo os canais de envio do código.
#
#  - **`identifier` (BE-048).** Código curto de 6 caracteres A-Z0-9 que o usuário lê e
#    dita por telefone. `smart_id`/`by_any_id` saiu no trim, então não há padrão a
#    reusar. A unicidade é garantida **pelo banco**, não só pela aplicação — a geração
#    é aleatória e o retry depende do índice para detectar colisão.
#
#  - **`is_phone_checked` (DEC-74).** O indicador "Verificação: {nível}" é replicado
#    como está, com o degrau "Máxima" dependendo desta flag. O que **não** é replicado é
#    a trava de edição do telefone que o legado amarrava nela
#    (`my_account/parts/phone/_container.js.erb:14-16`): no ai9 o telefone é canal de
#    login, e travá-lo deixaria quem perdeu o número sem acesso e sem autoatendimento.
class AddSafegoldIdentityColumnsToUsers < ActiveRecord::Migration[8.0]
  def change
    change_table :users, bulk: true do |t|
      t.datetime :blocked_at,
                 comment: 'DEC-39 — conta bloqueada. Colapsa `is_active` e `deactivated` do legado num campo só, e este é LIDO pelo gate central.'
      t.string :blocked_reason,
               comment: 'Motivo do bloqueio, exibido ao usuário na tela de login. Sem isto o bloqueio vira logout mudo (IMP-A17).'
      t.string :username,
               comment: 'DEC-45 — identificador alternativo do legado. IDENTIFICA, não recebe: o código de acesso sai por e-mail ou telefone.'
      t.string :identifier, limit: 6,
                            comment: 'BE-048 — código curto A-Z0-9 que o usuário dita por telefone. Unicidade garantida pelo banco.'
      t.boolean :is_phone_checked, default: false, null: false,
                                   comment: 'DEC-74 — degrau "Máxima" do indicador de verificação. NÃO trava a edição do telefone.'

      # Fechamento de órfãos do Phase 2 (F.1) — DB-540.
      t.integer :legacy_id,
                comment: 'DEC-12 — proveniência do registro na base do legado. Preservado, nunca reusado como chave.'
      t.uuid :manager_id,
             comment: 'Gestor direto (auto-relação). O legado não tinha índice aqui; este tem.'
      t.uuid :default_project_id,
               comment: 'FK LÓGICA para `projects`. Projeto sugerido no primeiro acesso. NÃO é autorização — quem autoriza é `memberships` (C1).'
      t.bigint :app_theme_id,
               comment: 'FK LÓGICA para o tema por usuário. As telas de auth NÃO leem daqui (a marca vem dos tokens do app, FE-501).'
      t.string :kind,
               comment: 'Classificação descritiva do legado (`users.kind`). Nunca consultada para autorizar.'
      t.string :color,
               comment: 'Cor do avatar/etiqueta. Cosmético.'

      # Perfil — os campos de `livetat_auth_user_infos` que cabem em `users` (tarefa 1.1).
      # `livetat_auth_user_infos` NÃO vira tabela: o que não cabe aqui vai para
      # `user_profiles` (F.3).
      t.string :gender,
               comment: 'Enum string: male, female, other, undisclosed. O legado guardava texto livre.'
      t.date :birthday,
             comment: 'Aniversário como DATE. No legado era string, e comparação de idade dependia de parse na view.'
      t.string :cnpj,
               comment: 'CNPJ da pessoa jurídica. `cpf_cnpj` continua sendo o documento principal.'
      t.string :fiscal_document_number,
               comment: 'Número do documento fiscal (RG/CNH).'
      t.date :fiscal_document_issued_at,
             comment: 'Data real de emissão. O legado guardava a data como string e aceitava "00/00/0000".'
      t.string :graduation,
               comment: 'Escolaridade/graduação declarada.'
    end

    add_index :users, :username, unique: true, where: 'username IS NOT NULL',
                                 name: 'index_users_on_username'
    add_index :users, :identifier, unique: true, where: 'identifier IS NOT NULL',
                                   name: 'index_users_on_identifier'
    add_index :users, :legacy_id, unique: true, where: 'legacy_id IS NOT NULL',
                                  name: 'index_users_on_legacy_id'
    add_index :users, :manager_id, name: 'index_users_on_manager_id'
    add_index :users, :default_project_id, name: 'index_users_on_default_project_id'
    add_index :users, :app_theme_id, name: 'index_users_on_app_theme_id'
    add_index :users, :blocked_at, where: 'blocked_at IS NOT NULL',
                                   name: 'index_users_on_blocked_at'
  end
end

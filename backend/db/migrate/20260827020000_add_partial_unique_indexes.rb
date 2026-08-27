# frozen_string_literal: true

# **DEC-127** — decisão registrada não é decisão implementada.
#
# Esta migration fecha a distância entre cinco decisões assinadas em
# `db/etl/decisions.yml` e o banco. Todas as cinco são **a mesma decisão**, tomada
# cinco vezes (DEC-119 ×3, DEC-125, DEC-128.4):
#
# > Nós derivamos unicidade da **intenção** do schema legado, e o legado usa
# > **vazio, sentinela e rótulo humano** como "não se aplica". Restrição desenhada
# > sem olhar o dado vira bloqueio na virada.
#
# O erro está no índice que **nós** desenhamos, não no dado do cliente: nenhuma
# linha é alterada, nenhuma é pulada.
#
# ## Os cinco casos, medidos contra o dump de 31/05/2025
#
# | índice | o que o dado real tem | como fica |
# | --- | --- | --- |
# | `carriers[bank_code]` | sentinelas `8888` (181×), NULL (83), `999` (31), `9999` (13), `888` (4); **zero** repetidos entre os códigos de verdade | único PARCIAL, ignorando NULL e os quatro sentinelas |
# | `users[username]` | 72 contas com `username` **vazio**, 11 com NULL; **zero** repetidos entre os 52 preenchidos | único PARCIAL, ignorando NULL **e vazio** |
# | `renegotiations[project_id+integration_key]` | 9 grupos, 82 linhas | único PARCIAL, só entre linhas **nascidas no ai9** |
# | `providers[project_id+integration_key]` | 6 grupos, 163 de 289 linhas (um com 119) | idem |
# | `availability_templates[…+title]` | 90 de 2.705 com título **vazio** | único PARCIAL, ignorando título vazio |
#
# ## Por que `providers` e `renegotiations` são PROVENIÊNCIA e não formato
#
# Nos outros três o "não se aplica" tem forma reconhecível — vazio, sentinela — e
# ela vale também para o dado de amanhã. Nesses dois **não vale**, e foi medido:
#
# * em `providers` os 6 rótulos repetidos estão em CAIXA e com acento (`SSA`,
#   `Fornecedor`, `Renegociação`, `Fidcs`, `Acionista`, `Colaboradores`) — forma
#   que `GlobalCatalog.slugify` nunca produz. Um predicado "só vale para chave em
#   caixa baixa" resolveria estes 6 e **abriria um buraco**: bastaria digitar a
#   chave com uma maiúscula para escapar da unicidade;
# * em `renegotiations` três dos nove grupos são chaves **legitimamente derivadas**
#   (`banco_bradesco`, `parcelamento_do_simples_absd`, `77800`). A chave sai de
#   `provider_name` (`renegotiation.rb:214`), e **um fornecedor tem várias
#   renegociações no mesmo projeto** — repetir é o comportamento correto do legado,
#   não sujeira. Nenhum predicado sobre o VALOR separa esses casos.
#
# O que separa é a **origem da linha**: `legacy_id IS NULL` é "nasceu no ai9".
# A unicidade passa a valer entre as linhas que o ai9 criar, e o histórico entra
# como está — que é exatamente o que as duas decisões autorizam ("as 289 linhas
# entram como estão", "nenhuma linha alterada nem pulada").
#
# ## Não bloqueante e reversível (Princípio 9)
#
# `CREATE INDEX CONCURRENTLY` / `DROP INDEX CONCURRENTLY`, fora de transação de
# DDL. A carga do cutover roda com o sistema de pé; um `CREATE INDEX` comum
# tomaria `SHARE` na tabela e pararia a escrita. Cada passo usa
# `if_exists`/`if_not_exists` para ser re-executável se a execução morrer no meio
# — que é o preço de abrir mão da transação.
#
# ## ⚠ A migration sozinha NÃO destrava
#
# Isto está medido e escrito na DEC-125: com o índice parcial e a validação do
# model intacta, a carga **ainda para** em `Integration key já está em uso neste
# projeto`. São sempre DUAS mudanças. As validações correspondentes estão em
# `provider.rb`, `renegotiation.rb`, `user.rb`, `carrier.rb` e
# `availability_template.rb`, e cada uma cita esta migration.
class AddPartialUniqueIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  # Os quatro "sem código bancário" do legado. São SENTINELAS, não bancos: não há
  # 181 portadores no mesmo banco.
  SENTINELAS_DE_BANCO = %w[888 999 8888 9999].freeze

  def up
    # ---------------------------------------------------------------- carriers
    # O índice único NUNCA existiu aqui (só o comum, de busca). A DEC-119 pede que
    # ele passe a existir na forma PARCIAL: entre os códigos de verdade não há um
    # único repetido, e é essa a regra que vale daqui para a frente.
    add_index :carriers, :bank_code,
              unique: true,
              where: "bank_code IS NOT NULL AND #{sentinelas_sql}",
              name: 'index_carriers_on_bank_code_real',
              algorithm: :concurrently,
              if_not_exists: true

    # ------------------------------------------------------------------- users
    # Era `WHERE username IS NOT NULL`, que deixa 72 strings VAZIAS colidirem entre
    # si. O conversor já as nulifica (`users.rb:98`, `.presence`), mas a trava é do
    # banco: qualquer outro caminho de escrita que grave '' derrubaria a segunda
    # linha.
    trocar_indice(
      :users, 'index_users_on_username',
      columns: :username, unique: true,
      where: "username IS NOT NULL AND username <> ''"
    )

    # ----------------------------------------------------------- renegotiations
    trocar_indice(
      :renegotiations, 'index_renegotiations_on_project_id_and_integration_key',
      columns: %i[project_id integration_key], unique: true,
      where: 'legacy_id IS NULL'
    )

    # ---------------------------------------------------------------- providers
    trocar_indice(
      :providers, 'index_providers_on_project_id_and_integration_key',
      columns: %i[project_id integration_key], unique: true,
      where: 'legacy_id IS NULL'
    )

    # ---------------------------------------------------- availability_templates
    # São DOIS índices, um para raiz e outro para filho, e os 90 títulos vazios
    # caem nos dois. Gerar título a partir do contexto foi RECUSADO (DEC-128.4):
    # seria texto que ninguém escreveu aparecendo na tela como se fosse do cliente.
    trocar_indice(
      :availability_templates, 'index_availability_templates_unique_root_title',
      columns: %i[type project_id title], unique: true,
      where: "parent_template_id IS NULL AND title <> ''"
    )
    trocar_indice(
      :availability_templates, 'index_availability_templates_unique_child_title',
      columns: %i[project_id parent_template_id title], unique: true,
      where: "parent_template_id IS NOT NULL AND title <> ''"
    )
  end

  def down
    remove_index :carriers, name: 'index_carriers_on_bank_code_real',
                 algorithm: :concurrently, if_exists: true

    trocar_indice(:users, 'index_users_on_username',
                  columns: :username, unique: true, where: 'username IS NOT NULL')
    trocar_indice(:renegotiations, 'index_renegotiations_on_project_id_and_integration_key',
                  columns: %i[project_id integration_key], unique: true, where: nil)
    trocar_indice(:providers, 'index_providers_on_project_id_and_integration_key',
                  columns: %i[project_id integration_key], unique: true, where: nil)
    trocar_indice(:availability_templates, 'index_availability_templates_unique_root_title',
                  columns: %i[type project_id title], unique: true, where: 'parent_template_id IS NULL')
    trocar_indice(:availability_templates, 'index_availability_templates_unique_child_title',
                  columns: %i[project_id parent_template_id title], unique: true,
                  where: 'parent_template_id IS NOT NULL')
  end

  private

  # Trocar predicado de índice é DROP + CREATE: o Postgres não altera o `WHERE` de
  # um índice existente. A ordem é **derrubar antes de criar** porque o nome é o
  # mesmo — e o nome é o mesmo de propósito, para que `schema.rb` continue legível
  # e ninguém precise saber que houve troca.
  def trocar_indice(tabela, nome, columns:, unique:, where:)
    remove_index tabela, name: nome, algorithm: :concurrently, if_exists: true
    add_index tabela, columns, unique: unique, where: where, name: nome,
              algorithm: :concurrently, if_not_exists: true
  end

  # **Uma comparação por sentinela, e não `NOT IN`.** O `NOT IN` vira `<> ALL
  # (ARRAY[…])` no catálogo, e o `schema.rb` o re-imprime de DUAS formas
  # diferentes conforme o índice tenha vindo de um `CREATE INDEX` ou de um
  # `schema:load` — o arquivo passava a alternar entre as duas a cada rodada.
  # `schema.rb` que muda sozinho é ruído que esconde a mudança de verdade.
  #
  # **As aspas são literais, e NÃO `connection.quote`** (OPS-549). O portão de
  # schema do destino re-executa toda migration contra um gravador que **não
  # toca em banco nenhum**; qualquer chamada a `connection` levanta
  # `UnknownDsl` e derruba o portão. Aqui não há o que escapar: os quatro
  # sentinelas são constantes de dígitos declaradas acima.
  def sentinelas_sql
    SENTINELAS_DE_BANCO.map { |codigo| "bank_code <> '#{codigo}'" }.join(' AND ')
  end
end

# frozen_string_literal: true

# S6 — os catálogos que o borderô consome: `wallets`, `receivable_kinds`,
# `movement_kinds` e a alíquota de IOF com vigência.
#
# Fecha **DB-158**, **DB-159**, **DB-160**, **DB-433**, **DB-559**, **DB-560**,
# **DB-563** e a parte de dados de **BE-160**.
#
# ### Catálogo GLOBAL, não escopado por projeto
#
# Os três são `GlobalCatalog` (contrato C1, regra 4): `wallets`,
# `receivable_kinds` e `movement_kinds` não têm `project_id` no legado
# (`20210317140156`, `20210317140206`, `20210317151301`) e não podem ganhar um
# aqui — um borderô de 2022 aponta para a carteira 8 e ela precisa continuar
# visível em todo projeto.
#
# ### Índice único no TÍTULO — corrige o D-12
#
# No legado a unicidade era só `validates :title, uniqueness: true`, isto é, um
# `SELECT` seguido de um `INSERT`: duas abas gravando ao mesmo tempo criam duas
# carteiras "Fomento". O índice fecha a corrida no banco.
#
# ### `resource_sources` nasce aqui POR DEPENDÊNCIA DE FK — a dona é a S8
#
# `receivable_entries.resource_source_id` é **obrigatório** no legado
# (`../sfg/app/models/receivable_entry.rb:16`) e medido: **28.131 de 28.131**
# linhas de produção têm a coluna preenchida. A tabela é de `DB-287`/`DB-562`,
# da **S8**, que roda DEPOIS de S6 na corrente (S6 → S7 → S8). Mesmo precedente
# da S5, que criou `risk_operations` (da S7) por dependência de FK e escreveu o
# dono no comentário da tabela.
#
# **S8: a tabela JÁ EXISTE. Não a recrie** — recriar tabela apaga em silêncio as
# colunas que migrations posteriores acrescentaram (`checkpoint.md`, armadilha
# 2). Endpoints, `is_active` (Q-R19) e o conteúdo final do seed (`DB-293`)
# continuam sendo da S8.
#
# ### `resource_kinds` NÃO nasce, e `receivable_entries.resource_kind_id` também não
#
# Medido no dump de produção: a tabela tem **0 linhas** e **0 de 28.131**
# borderôs têm `resource_kind_id`. Fecha o portão **T-D7** da S8 e a **DEC-82**
# com evidência. A família inteira (`BE-307`, `BE-720`…`BE-724`, `FE-307`,
# `DB-286`, `DB-289`, `DB-294`) é `dropped`.
#
# ### `iof_rates` — corrige o D-15
#
# No legado as alíquotas `0.000041` (ao dia) e `0.0038` (fixa) estão **cravadas
# na fórmula** (`receivable_entry.rb:54`). Recalcular um borderô de 2022 hoje
# usaria a alíquota de hoje, em silêncio. Aqui a alíquota tem vigência e é
# **resolvida pela data da operação**, fora do calculador, que continua puro.
class CreateReceivableCatalogs < ActiveRecord::Migration[8.0]
  def change
    create_table :wallets, id: :uuid, default: -> { 'gen_random_uuid()' },
                           comment: 'Carteira do borderô (Antecipação, Desconto, Fomento…). Catálogo GLOBAL — sem escopo de projeto (C1, regra 4).' do |t|
      t.string :title, null: false, comment: 'Nome da carteira. Único no banco — fecha o D-12 (corrida entre duas abas).'
      t.string :integration_key, null: false,
                                 comment: 'Chave de integração, derivada do título na CRIAÇÃO e congelada depois (DC-22).'
      t.boolean :is_active, null: false, default: true,
                            comment: 'Ativa. NÃO filtra listagem nem select (Q-B12) — era integer nullable no legado e nunca foi aplicada.'
      t.uuid :user_id, comment: 'Autor do cadastro. Informativo: seed e ETL gravam sem autor.'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado (`wallets.id`).'

      t.timestamps
    end
    add_index :wallets, :title, unique: true
    add_index :wallets, :integration_key, unique: true
    add_index :wallets, :legacy_id, unique: true

    create_table :receivable_kinds, id: :uuid, default: -> { 'gen_random_uuid()' },
                                    comment: 'Tipo de recebível (Duplicata, Cheque, ACC…). Catálogo GLOBAL — sem escopo de projeto (C1, regra 4).' do |t|
      t.string :title, null: false, comment: 'Nome do tipo. Único no banco — fecha o D-12.'
      t.string :integration_key, null: false, comment: 'Chave de integração, derivada do título na CRIAÇÃO e congelada depois.'
      t.boolean :is_active, null: false, default: true, comment: 'Ativo. Sem efeito em filtro (Q-B12), como no legado.'
      t.uuid :user_id, comment: 'Autor do cadastro. Informativo.'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência (`receivable_kinds.id`).'

      t.timestamps
    end
    add_index :receivable_kinds, :title, unique: true
    add_index :receivable_kinds, :integration_key, unique: true
    add_index :receivable_kinds, :legacy_id, unique: true

    create_table :movement_kinds, id: :uuid, default: -> { 'gen_random_uuid()' },
                                  comment: 'Tipo de movimentação/tarifa (AdValorem, Deságio, IOF, TAC…). Catálogo GLOBAL. É ele que classifica a tarifa nos 4 buckets do cálculo.' do |t|
      t.string :title, null: false, comment: 'Nome do tipo. Único no banco.'
      t.string :integration_key, null: false, comment: 'Chave de integração, derivada do título na CRIAÇÃO e congelada depois (BE-446).'
      t.boolean :is_active, null: false, default: true, comment: 'Ativo. Sem efeito em filtro (Q-B12).'

      # Os quatro classificadores. `BE-447`: no máximo UM pode estar ligado —
      # a validação existe no legado (`movement_kind.rb:12-17`) e é o que
      # garante que uma tarifa caia em um único bucket. Conferido em produção:
      # nenhuma das 18 linhas tem mais de um ligado.
      t.boolean :is_advalorem, null: false, default: false, comment: 'Classificador AdValorem. Soma em `tarifas_ad_valorem` e entra na base do IOF.'
      t.boolean :is_desagio, null: false, default: false, comment: 'Classificador Deságio. Soma em `tarifas_desagio` e entra na base do IOF.'
      t.boolean :is_iof, null: false, default: false, comment: 'Classificador IOF. Soma em `tarifas_iof`.'
      t.boolean :is_liquidation, null: false, default: false,
                                  comment: 'Classificador Liquidação. PORTADO SEM CONSUMIDOR (D-74, Q-B13) — nenhuma regra o lê, nem no legado.'

      t.boolean :is_operation, null: false, default: false,
                               comment: 'Aparece na lista de tarifas do formulário de borderô. É o único dos flags de exibição que tem leitor.'
      t.boolean :is_title, null: false, default: false,
                           comment: 'PORTADO SEM CONSUMIDOR (D-74, Q-B13). Nenhuma regra o lê.'

      t.string :kind, comment: 'Sentido contábil: `credit` ou `debit`. No legado era o texto pt-BR "Crédito"/"Débito" (BE-445, mesmo tratamento do `status`).'
      t.uuid :user_id, comment: 'Autor do cadastro. Informativo.'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência (`movement_kinds.id`).'

      t.timestamps
    end
    add_index :movement_kinds, :title, unique: true
    add_index :movement_kinds, :integration_key, unique: true
    add_index :movement_kinds, :legacy_id, unique: true
    add_check_constraint :movement_kinds,
                         "kind IS NULL OR kind IN ('credit', 'debit')",
                         name: 'movement_kinds_kind_check'
    # `BE-447` no banco, não só no model: dois classificadores ligados na mesma
    # linha é dado que quebra a soma dos buckets em silêncio.
    add_check_constraint :movement_kinds,
                         'is_advalorem::int + is_desagio::int + is_iof::int + is_liquidation::int <= 1',
                         name: 'movement_kinds_single_tax_kind_check'

    # ------------------------------------------------------------------
    # `resource_sources` — DONA: S8. Ver o cabeçalho.
    # ------------------------------------------------------------------
    create_table :resource_sources, id: :uuid, default: -> { 'gen_random_uuid()' },
                                    comment: 'Fonte do recurso do borderô (Caixa, Fomento, Recompra…). Catálogo GLOBAL. Tabela criada em S6 por dependência de FK de `receivable_entries`; o COMPORTAMENTO (endpoints BE-308/BE-725..729, seed DB-293, Q-R19) é da S8.' do |t|
      t.string :title, null: false, comment: 'Nome da fonte. Único no banco.'
      t.string :integration_key, null: false, comment: 'Chave de integração, derivada do título na CRIAÇÃO e congelada depois.'
      t.boolean :is_active, null: false, default: true, comment: 'Ativa. NÃO filtra o select do borderô (Q-R19) — fonte desativada some do formulário se filtrar.'
      t.uuid :user_id, comment: 'Autor do cadastro. Informativo.'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência (`resource_sources.id`).'

      t.timestamps
    end
    add_index :resource_sources, :title, unique: true
    add_index :resource_sources, :integration_key, unique: true
    add_index :resource_sources, :legacy_id, unique: true

    # ------------------------------------------------------------------
    # `iof_rates` — BE-160 (parte de dados). Corrige o D-15.
    # ------------------------------------------------------------------
    create_table :iof_rates, id: :uuid, default: -> { 'gen_random_uuid()' },
                             comment: 'Alíquota de IOF com VIGÊNCIA. Corrige o D-15: no legado as duas alíquotas estavam cravadas na fórmula e um recálculo histórico usava a de hoje.' do |t|
      t.decimal :daily_rate, precision: 12, scale: 8, null: false,
                             comment: 'Alíquota por dia de prazo. `0.000041` desde a origem — `receivable_entry.rb:54`.'
      t.decimal :fixed_rate, precision: 12, scale: 8, null: false,
                             comment: 'Alíquota fixa sobre a base. `0.0038` desde a origem — `receivable_entry.rb:54`.'
      t.date :valid_from, null: false, comment: 'Início da vigência, inclusivo.'
      t.date :valid_to, comment: 'Fim da vigência, inclusivo. NULO = vigência aberta.'
      t.string :note, comment: 'Por que esta alíquota mudou. Em branco na linha de origem: o legado nunca teve outra.'

      t.timestamps
    end
    add_index :iof_rates, :valid_from
    add_check_constraint :iof_rates,
                         'valid_to IS NULL OR valid_to >= valid_from',
                         name: 'iof_rates_period_check'
  end
end

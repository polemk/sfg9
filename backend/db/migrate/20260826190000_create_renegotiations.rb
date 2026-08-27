# frozen_string_literal: true

# S9 / DB-190, DB-195, DB-196, DB-197, DB-198, DB-568 — **renegociação**.
#
# A renegociação é a dívida negociada com um fornecedor: parcelada, paga ao longo
# do tempo e documentada por anexos. A tabela guarda **o cadastro** (13 campos que
# o usuário digita) e **~20 agregados derivados** das parcelas e dos pagamentos.
#
# Cinco decisões, todas com defeito legado correspondente:
#
# 1. **Os agregados continuam PERSISTIDOS.** Não é preguiça: a listagem mostra 13
#    colunas de resumo e o dashboard (S15) lê o contador de vencidas. Derivar tudo
#    por consulta em toda listagem seria N consultas por linha — o mesmo N+2 que o
#    legado tinha em `calculate_next_installment_*`. Quem os escreve é UM serviço
#    (`Renegotiations::AggregateService`, contrato C2), nunca um `save` espalhado.
# 2. **`kind` e `state` têm domínio FECHADO no banco** (D-B9), por CHECK. No legado
#    eram `string` livre com quatro constantes de classe, e um `update` por
#    parâmetro escrevia qualquer coisa. **Os valores continuam em português**
#    porque são DADO de produção que o ETL copia e a tela exibe (DEC-30) — não são
#    enum novo do ai9.
# 3. **`decimal(15,2)` para dinheiro, `float` para percentual e taxa** (D-B4 /
#    DB-196), divergindo conscientemente do `decimal(14,2)` da convenção §4: é o
#    tipo que o legado usa, e a cadeia truncamento→float→arredondamento é
#    replicada (DEC-02 / D-104).
# 4. **`attachments_count` é `null: false, default: 0`** (DB-195). No legado a
#    coluna nascia NULL e `has_attachments?` fazia `nil > 0` → `NoMethodError` na
#    renderização do detalhe.
# 5. **FKs e índices existem.** Corrige **D-103**: NENHUMA das migrations de
#    renegociação do legado tem índice ou chave estrangeira — nem em
#    `project_id`, nem em `provider_id`, nem em `renegotiation_id`.
#
# **`UNIQUE (id, project_id)`** não é redundante: é o alvo da FK composta que as
# parcelas usam para que o banco — e não só o serviço — garanta que parcela e
# renegociação estão no MESMO projeto (contrato C1 no nível do esquema).
class CreateRenegotiations < ActiveRecord::Migration[8.0]
  KINDS = %w[Financeiro Operacional Tributario Trabalhista].freeze
  STATES = ['Liquidado', 'Pago', 'Inconsistente', 'Sem parcela cadastrada'].freeze

  def change
    create_table :renegotiations, id: :uuid, default: -> { 'gen_random_uuid()' },
                                  comment: 'Dívida renegociada com um fornecedor. Escopada por projeto (C1).' do |t|
      # --- Vínculos ---------------------------------------------------------
      t.uuid :project_id, null: false, comment: 'Projeto dono. Obrigatório (C1). Nunca vem do corpo da requisição.'
      t.uuid :provider_id, null: false, comment: 'Fornecedor (contraparte da dívida).'
      t.uuid :company_id, null: false,
                          comment: 'Empresa do projeto que deve. Obrigatória desde 2022 (`add_company_to_renegotiation`).'

      # --- Cadastro ---------------------------------------------------------
      t.string :title, null: false, comment: 'Nome da renegociação. Nasce igual ao nome do fornecedor quando em branco.'
      t.string :provider_name, null: false,
                               comment: 'Nome do fornecedor COPIADO na gravação (`provider.title`). Carimbo, não junção.'
      t.string :kind, null: false, comment: "Tipo: #{KINDS.join(' | ')}. Domínio fechado por CHECK (D-B9)."
      t.string :integration_key, null: false,
                                 comment: 'Chave de integração derivada do nome do fornecedor. ÚNICA POR PROJETO — ' \
                                          'no legado dois fornecedores homônimos colidiam em silêncio.'
      t.date :renegotiation_date, null: false, comment: 'Data da negociação.'
      t.text :observation, comment: 'Observações livres.'
      t.string :origin, comment: 'Origem: minuta bancária, fornecedor, fundo.'
      t.string :monetary_correction, comment: 'Índice de correção monetária, texto livre (o legado nunca o calculou).'
      t.boolean :has_safegold_management, null: false, default: false,
                                          comment: 'Carimbo COPIADO do projeto na criação e NUNCA ressincronizado ' \
                                                   '(D-30, Q-B32). Não tem consumidor — portado por paridade.'

      # --- Valores do cadastro (decimal 15,2 — D-B4) ------------------------
      t.decimal :original_value, precision: 15, scale: 2, null: false, default: 0,
                                 comment: 'Valor Original Vencido. Zero e negativo continuam aceitos (Q-B21).'
      t.decimal :original_pending_value, precision: 15, scale: 2, null: false, default: 0,
                                         comment: 'Valor Original A Vencer.'
      t.decimal :additional_value, precision: 15, scale: 2, null: false, default: 0,
                                   comment: 'Despesas adicionais (exceto juros).'
      t.decimal :total_debt, precision: 15, scale: 2, null: false, default: 0,
                             comment: 'Valor Total da Dívida (com juros projetados). É a referência de consistência.'
      t.decimal :desagio_value, precision: 15, scale: 2, null: false, default: 0, comment: 'Valor do deságio.'
      t.decimal :correct_value, precision: 15, scale: 2, null: false, default: 0,
                                comment: 'Valor Atualizado até a data de correção. **SEMPRE igual a `total_debt`** ' \
                                         '— `interest_rate_correction` e `grace_period` nunca são lidos (D-47, Q-B24).'

      # --- Taxas e prazos (float — D-B4) ------------------------------------
      t.float :interest_rate_correction, null: false, default: 0,
                                         comment: 'Taxa de juros de correção. Fica na tabela e NUNCA é lida (D-47).'
      t.integer :grace_period, null: false, default: 0,
                               comment: 'Carência em dias. Idem: existe e nunca é lida (D-47).'
      t.float :operation_interest_rate, null: false, default: 0,
                                        comment: 'Taxa de juros acordada, em % ao período. Entra no VP (`current_value`).'

      # --- Agregados derivados das PARCELAS ---------------------------------
      t.decimal :installments_main_value, precision: 15, scale: 2, null: false, default: 0,
                                          comment: 'Soma do PRINCIPAL das parcelas. Renomeada de `total_value` em ' \
                                                   '29/04/2022 COM MUDANÇA DE SEMÂNTICA (DEC-94): era "R$ Total".'
      t.decimal :installments_interest_value, precision: 15, scale: 2, null: false, default: 0,
                                              comment: 'Soma dos juros das parcelas.'
      t.decimal :installments_main_value_with_interest, precision: 15, scale: 2, null: false, default: 0,
                                                        comment: 'Principal + juros.'
      t.decimal :installments_monetary_correction_value, precision: 15, scale: 2, null: false, default: 0,
                                                         comment: 'Soma da correção monetária das parcelas.'
      t.decimal :installments_main_value_with_interest_cm, precision: 15, scale: 2, null: false, default: 0,
                                                           comment: 'Principal + juros + correção monetária.'
      t.decimal :main_value, precision: 15, scale: 2, null: false, default: 0,
                             comment: 'Valor total da renegociação = `installments_main_value_with_interest_cm`. ' \
                                      'NÃO é `total_debt`: é o que as parcelas somam, não o que foi contratado.'

      # --- Agregados derivados dos PAGAMENTOS -------------------------------
      t.decimal :paid_value_with_interest_cm, precision: 15, scale: 2, null: false, default: 0,
                                              comment: 'Soma do pago (principal+juros+CM), SEM mora.'
      t.decimal :late_payment_value, precision: 15, scale: 2, null: false, default: 0,
                                     comment: 'Soma da mora das parcelas.'
      t.decimal :paid_value, precision: 15, scale: 2, null: false, default: 0,
                             comment: 'R$ Pago = mora + pago sem mora. **Conta a mora**, ao contrário de ' \
                                      '`remaining_value`, que a ignora. A assimetria é do legado e é preservada.'
      t.decimal :pending_main_value, precision: 15, scale: 2, null: false, default: 0,
                                     comment: 'Pendente = `main_value` - pago sem mora. **PODE FICAR NEGATIVO** ' \
                                              '(Q-B22): mede a mesma coisa que `remaining_value` com outra regra.'
      t.decimal :remaining_value, precision: 15, scale: 2, null: false, default: 0,
                                  comment: 'R$ A Pagar = soma de `pending_value` das parcelas, que tem PISO EM ZERO. ' \
                                           'Por isso nunca fica negativo, e por isso diverge de `pending_main_value`.'
      t.float :paid_percent, null: false, default: 0,
                             comment: '% pago = 100 * pago_sem_mora / main_value, arredondado a 2 casas. Divisão por ' \
                                      'zero devolve 0; resultado acima de 100% é ACEITO (Q-B21).'

      # --- Contagens e datas -------------------------------------------------
      t.integer :installments_count, null: false, default: 0, comment: 'Quantidade de parcelas.'
      t.integer :paid_installments, null: false, default: 0, comment: 'Parcelas quitadas.'
      t.integer :overdue_installments, null: false, default: 0,
                                       comment: 'Parcelas vencidas e não pagas. **Deixa de depender do cron diário** ' \
                                                '(D-54 / D-B6 / OPS-190): é recalculada em toda alteração e a leitura ' \
                                                'da API a apura na CONSULTA. O número não muda; muda quando fica certo.'
      t.integer :due_installments, null: false, default: 0,
                                   comment: '"A vencer" = total - pagas. **INCLUI as vencidas** (Q-B23) — o nome ' \
                                            'mente, a conta é essa, e é ela que entra no VP.'
      t.date :first_due_date, comment: 'Primeiro vencimento.'
      t.date :last_due_date, comment: 'Último vencimento.'
      t.decimal :current_installment_value, precision: 15, scale: 2, null: false, default: 0,
                                            comment: 'Valor Parcela: soma das parcelas do MÊS CORRENTE — e, quando há ' \
                                                     'juros > 0 e saldo em aberto, **SOBRESCRITA pelo VP** (D-46, Q-B25).'
      t.decimal :current_value, precision: 15, scale: 2, null: false, default: 0,
                                comment: 'VP — valor presente da dívida pela taxa acordada.'
      t.decimal :total_value_with_desagio, precision: 15, scale: 2, null: false, default: 0,
                                           comment: 'Valor original - deságio. Deságio maior que o original é aceito.'

      t.string :state, null: false, default: 'Sem parcela cadastrada',
                       comment: "Status: #{STATES.join(' | ')}. Domínio fechado por CHECK (D-B9)."

      # --- Anexos ------------------------------------------------------------
      t.integer :attachments_count, null: false, default: 0,
                                    comment: 'Contador de anexos (DB-195). `null: false, default: 0` porque no legado ' \
                                             'o NULL fazia `nil > 0` levantar `NoMethodError` ao abrir o detalhe.'

      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    # --- Índices das consultas quentes (DB-198) -----------------------------
    add_index :renegotiations, :project_id
    add_index :renegotiations, %i[project_id integration_key], unique: true
    add_index :renegotiations, %i[project_id state]
    add_index :renegotiations, %i[project_id kind]
    add_index :renegotiations, :provider_id
    add_index :renegotiations, :company_id
    add_index :renegotiations, :legacy_id, unique: true
    # A busca casa `title` E `provider_name` (BE-190). Sem estes dois índices a
    # listagem varre a tabela a cada tecla digitada.
    add_index :renegotiations, :title
    add_index :renegotiations, :provider_name

    # Alvo da FK composta das parcelas — ver o cabeçalho.
    add_index :renegotiations, %i[id project_id], unique: true, name: 'index_renegotiations_on_id_and_project'

    add_foreign_key :renegotiations, :projects, column: :project_id
    add_foreign_key :renegotiations, :providers, column: :provider_id
    add_foreign_key :renegotiations, :companies, column: :company_id

    add_check_constraint :renegotiations,
                         "kind IN (#{KINDS.map { |k| "'#{k}'" }.join(', ')})",
                         name: 'renegotiations_kind_domain'
    add_check_constraint :renegotiations,
                         "state IN (#{STATES.map { |s| "'#{s}'" }.join(', ')})",
                         name: 'renegotiations_state_domain'
    add_check_constraint :renegotiations, 'attachments_count >= 0',
                         name: 'renegotiations_attachments_count_non_negative'
  end
end

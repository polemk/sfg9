# frozen_string_literal: true

# S9 / DB-191, DB-198, DB-569 — **parcelas (previsões) da renegociação**.
#
# Quatro decisões:
#
# 1. **Índice ÚNICO `(renegotiation_id, due_date)`.** No legado a unicidade era só
#    `validates_uniqueness_of :due_date, scope: [:renegotiation_id]` — checagem em
#    Ruby, sujeita a corrida entre duas abas (**D-12**). E o lote de criação
#    conferia sobreposição **contra as parcelas existentes**, nunca **dentro do
#    próprio lote**: um lote com duas datas iguais criava a primeira, a segunda
#    falhava em silêncio (o retorno de `create` era ignorado) e a resposta era
#    "criadas com sucesso".
#
# 2. **`project_id` é DENORMALIZADO aqui, e coerente com a renegociação POR FK
#    COMPOSTA.** Duas razões concretas, nenhuma delas estética:
#    - o `ProjectResetService` apaga por `project_id` na ordem folha→raiz; sem a
#      coluna, a parcela ficava e o `DELETE` da renegociação esbarrava na FK;
#    - a checagem C1 de um `renegotiation_installment_id` que chega por parâmetro
#      passa a ser uma comparação de coluna, não uma junção.
#    A FK composta `(renegotiation_id, project_id) → renegotiations(id, project_id)`
#    faz o **banco** garantir que parcela e renegociação estão no mesmo projeto.
#    Sem ela a denormalização seria só mais um lugar para o dado divergir.
#
# 3. **`saldo` (negativo) e `pending_value` (positivo, com piso em zero) coexistem
#    com semânticas diferentes** — e é de propósito. `saldo = pago - devido` fica
#    negativo enquanto falta pagar; `pending_value` é `devido - pago` quando
#    `saldo < 0` e **zero** caso contrário. É a raiz da assimetria que aparece lá
#    em cima em `pending_main_value` × `remaining_value` (Q-B22).
#
# 4. **`is_paid` vira BOOLEAN.** Era `integer default 0` comparado com `== 1`;
#    qualquer outro inteiro significava "não paga" sem que ninguém tivesse dito.
#    Mesma correção que a S4 fez em `providers.is_active`.
#
# **`number` é o ordinal da parcela** (`installment` no legado). Renomeado por um
# motivo prático: `renegotiation_installments.installment` é uma coluna que se
# nomeia a si mesma, e o escritor do seed de demonstração (S20) já grava `number`.
# O ETL da S14 mapeia coluna a coluna de qualquer forma — nenhum conversor é cópia
# cega, porque todo id inteiro do legado vira uuid aqui.
class CreateRenegotiationInstallments < ActiveRecord::Migration[8.0]
  def change
    create_table :renegotiation_installments, id: :uuid, default: -> { 'gen_random_uuid()' },
                                              comment: 'Parcela (previsão) de uma renegociação.' do |t|
      t.uuid :renegotiation_id, null: false, comment: 'Renegociação dona.'
      t.uuid :project_id, null: false,
                          comment: 'Projeto, denormalizado da renegociação e garantido por FK COMPOSTA (C1).'

      t.integer :number, comment: 'Ordinal da parcela (1..N), renumerado por vencimento. `installment` no legado.'
      t.date :due_date, null: false, comment: 'Vencimento. ÚNICO por renegociação, agora no banco (corrige D-12).'
      t.integer :month, comment: 'Mês do vencimento, copiado. Acompanha `due_date` (é o filtro da parcela do mês).'
      t.integer :year, comment: 'Ano do vencimento, copiado.'

      # --- Valores (decimal 15,2 — D-B4) -------------------------------------
      t.decimal :main_value, precision: 15, scale: 2, null: false, default: 0,
                             comment: 'PRINCIPAL da parcela. Obrigatoriamente > 0. Renomeada de `value` em ' \
                                      '29/04/2022 COM MUDANÇA DE SEMÂNTICA (DEC-94): era o valor total da parcela.'
      t.decimal :interest_value, precision: 15, scale: 2, null: false, default: 0, comment: 'Juros da parcela.'
      t.decimal :main_value_with_interest, precision: 15, scale: 2, null: false, default: 0,
                                           comment: 'principal + juros.'
      t.decimal :monetary_correction_value, precision: 15, scale: 2, null: false, default: 0,
                                            comment: 'Correção monetária da parcela.'
      t.decimal :main_value_with_interest_cm, precision: 15, scale: 2, null: false, default: 0,
                                              comment: 'principal + juros + correção. É o que soma no `main_value` ' \
                                                       'da renegociação e no "Valor Parcela" do mês.'
      t.decimal :late_payment_value, precision: 15, scale: 2, null: false, default: 0,
                                     comment: 'Mora, somada dos PAGAMENTOS. Entra no DEVIDO (aqui) e no PAGO ' \
                                              '(`total_paid_value` do pagamento) — os dois lados (Q-B26).'
      t.decimal :installment_total_value, precision: 15, scale: 2, null: false, default: 0,
                                          comment: 'Devido = principal+juros+CM + mora.'
      t.decimal :paid_value, precision: 15, scale: 2, null: false, default: 0,
                             comment: 'Pago = soma de `total_paid_value` dos pagamentos (já inclui a mora).'
      t.decimal :saldo, precision: 15, scale: 2, null: false, default: 0,
                        comment: 'pago - devido. **NEGATIVO** enquanto falta pagar. Nome em português preservado: ' \
                                 'é a coluna do legado e o ETL a copia (DEC-30).'
      t.decimal :pending_value, precision: 15, scale: 2, null: false, default: 0,
                                comment: 'devido - pago quando `saldo < 0`, senão ZERO. **Piso em zero** — é o que ' \
                                         'faz `remaining_value` nunca ficar negativo (Q-B22).'

      t.boolean :is_paid, null: false, default: false, comment: 'Quitada = `pending_value <= 0`. Era integer 0/1.'

      # --- Identidade do lote -------------------------------------------------
      t.uuid :batch_token, null: false,
                           comment: 'Identidade do lote de criação: parcelas criadas juntas compartilham o token.'
      t.string :color, limit: 9,
                       comment: 'Cor do lote (#rrggbb), para a tela distinguir lotes. Gerada com TERMINAÇÃO ' \
                                'GARANTIDA (OPS-196) — o laço de rejeição do legado não termina quando o espaço ' \
                                'de cores esgota.'

      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    add_index :renegotiation_installments, :renegotiation_id
    add_index :renegotiation_installments, %i[renegotiation_id due_date], unique: true,
                                                                          name: 'index_reneg_installments_unique_due_date'
    add_index :renegotiation_installments, %i[renegotiation_id number],
              name: 'index_reneg_installments_on_number'
    add_index :renegotiation_installments, :project_id
    add_index :renegotiation_installments, :due_date
    add_index :renegotiation_installments, %i[renegotiation_id is_paid],
              name: 'index_reneg_installments_on_is_paid'
    # Contagem de vencidas na CONSULTA (OPS-190): sem este índice parcial a
    # apuração ao vivo trocaria uma janela de 24 h por uma varredura.
    add_index :renegotiation_installments, %i[project_id due_date],
              where: 'is_paid = false', name: 'index_reneg_installments_overdue'
    add_index :renegotiation_installments, :batch_token
    add_index :renegotiation_installments, :legacy_id, unique: true

    # Alvo da FK composta dos pagamentos (DB-192).
    add_index :renegotiation_installments, %i[id renegotiation_id], unique: true,
                                                                    name: 'index_reneg_installments_id_and_reneg'

    add_foreign_key :renegotiation_installments, :projects, column: :project_id
    # A FK COMPOSTA. É ela — e não o serviço — que garante o contrato C1 no
    # esquema: não existe parcela cujo projeto difira do da renegociação.
    add_foreign_key :renegotiation_installments, :renegotiations,
                    column: %i[renegotiation_id project_id],
                    primary_key: %i[id project_id],
                    name: 'fk_reneg_installments_renegotiation_project'

    add_check_constraint :renegotiation_installments, 'main_value > 0',
                         name: 'reneg_installments_main_value_positive'
    add_check_constraint :renegotiation_installments, 'pending_value >= 0',
                         name: 'reneg_installments_pending_value_non_negative'
  end
end

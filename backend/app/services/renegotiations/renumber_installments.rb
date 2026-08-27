# frozen_string_literal: true

module Renegotiations
  # S9 / BE-203, OPS-195 — **renumeração das parcelas por vencimento**.
  #
  # `update_all`, **sem callbacks**, de propósito e por dois motivos:
  #
  # 1. **Não recursar.** No legado a parcela tinha `after_destroy` chamando
  #    `renegotiation.update_values!` e `update_installment_numbers!`, e o
  #    `update_values!` da parcela chamava a renegociação de volta. Renumerar com
  #    callbacks ligados dispara o recálculo uma vez **por parcela**.
  # 2. **Só o ordinal muda.** Renumerar não é evento de negócio: não altera valor,
  #    não altera vencimento, não muda o que o cliente deve. Passar por `save`
  #    faria a trilha (`paper_trail`) registrar N versões que não dizem nada.
  #
  # O legado usava `RenegotiationInstallment.import … on_duplicate_key_update`
  # (activerecord-import). Aqui é um `UPDATE … CASE`: uma consulta, sem gem, e sem
  # o risco de o `import` reescrever colunas que não deveria.
  class RenumberInstallments
    class << self
      def call(renegotiation)
        ids = RenegotiationInstallment
              .where(renegotiation_id: renegotiation.id)
              .order(due_date: :asc, created_at: :asc, id: :asc)
              .pluck(:id)
        return 0 if ids.empty?

        aplicar(RenegotiationInstallment.where(id: ids), ids)
      end

      # Compartilhado com `RenumberPayments`: o `UPDATE … CASE` é o mesmo, muda a
      # coluna e a ordem.
      def aplicar(scope, ids, coluna: :number)
        casos = ids.each_with_index.map do |id, indice|
          "WHEN #{ActiveRecord::Base.connection.quote(id)} THEN #{indice + 1}"
        end

        scope.update_all(
          Arel.sql("#{coluna} = CASE id #{casos.join(' ')} END, updated_at = NOW()")
        )
      end
    end
  end
end

# frozen_string_literal: true

module Renegotiations
  # S9 / BE-202 — **exclusão de parcelas em lote**. Corrige o **D-51**, que é
  # perda de dado documentada.
  #
  # O legado (`renegotiation.rb:61-70`):
  #
  #     def batch_destroy_installments!(ids)
  #       inst = nil
  #       inst = self.installments.where(id: ids) unless ids.blank?
  #       unless inst.blank?
  #         inst.destroy_all
  #         self.update_values!
  #         self.update_installment_numbers!
  #       end
  #       return inst.blank?          # ← o retorno
  #     end
  #
  # Três problemas na mesma dúzia de linhas:
  #
  # 1. **O retorno é `inst.blank?` DEPOIS do `destroy_all`.** A relação foi
  #    esvaziada, então `blank?` é `true` justamente quando a remoção **deu
  #    certo** — e o controller respondia `:ok` para `@success`, ou seja, sucesso
  #    quando nada havia para apagar e "falha" quando apagou. Na prática o usuário
  #    via **erro depois de uma remoção bem-sucedida**, reexecutava a ação e
  #    apagava **parcelas a mais**. É o D-51: perda de dado por mensagem invertida.
  # 2. **Remoção parcial passava por remoção total.** Ids inválidos ou de outra
  #    renegociação simplesmente não entravam no `where`, e ninguém era avisado.
  # 3. **`destroy_all` sem transação**, com `after_destroy` recalculando a
  #    renegociação **uma vez por parcela**.
  #
  # Aqui: **ou o lote inteiro sai, ou nada sai.** Id desconhecido, id de outra
  # renegociação e parcela **com pagamento** interrompem a operação **antes** de
  # qualquer `DELETE`, e a resposta diz exatamente qual. Lote vazio **não é
  # sucesso**.
  class BatchDestroyInstallments
    class << self
      include Result

      def call(renegotiation:, installment_ids:)
        ids = Array(installment_ids).map(&:to_s).uniq.reject(&:blank?)
        return unprocessable('Selecione ao menos uma parcela para remover.') if ids.empty?

        # O escopo é a renegociação — que já veio de `current_project!`. Um id de
        # outra renegociação (ou de outro projeto) simplesmente não é encontrado.
        parcelas = RenegotiationInstallment.where(renegotiation_id: renegotiation.id, id: filtrar_uuids(ids)).to_a

        faltando = ids - parcelas.map { |p| p.id.to_s }
        if faltando.any?
          return unprocessable(
            "#{faltando.size} parcela(s) selecionada(s) não pertencem a esta renegociação. Nada foi removido."
          )
        end

        com_pagamento = RenegotiationPayment
                        .where(renegotiation_installment_id: parcelas.map(&:id))
                        .distinct
                        .pluck(:renegotiation_installment_id)
        if com_pagamento.any?
          numeros = parcelas.select { |p| com_pagamento.include?(p.id) }.map { |p| "##{p.number}" }.sort
          return unprocessable(
            "Não é possível remover: #{numeros.join(', ')} tem pagamento lançado. Nada foi removido."
          )
        end

        remover!(renegotiation, parcelas)
      end

      private

      def remover!(renegotiation, parcelas)
        RenegotiationInstallment.transaction do
          RenegotiationInstallment.where(id: parcelas.map(&:id)).delete_all
          RenumberInstallments.call(renegotiation)
          AggregateService.recalculate!(renegotiation, broadcast: false)
        end

        RenegotiationChannel.publish_changed(renegotiation)
        ok({ deleted: parcelas.size })
      end

      # Id malformado vira "não pertence a esta renegociação", não
      # `PG::InvalidTextRepresentation` — 500 numa URL digitada errada é ruído.
      def filtrar_uuids(ids)
        ids.select { |id| id.match?(ProjectScopedService::UUID_FORMAT) }
      end
    end
  end
end

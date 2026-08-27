# frozen_string_literal: true

module Charges
  # S6 / **BE-189** — inclusão e remoção de recibos num pacote, **em lote**.
  #
  # ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
  #
  # Espelho de `../sfg/app/controllers/pub/charges_controller.rb` + o
  # `after_create`/`after_destroy` de `../sfg/app/models/receipt.rb:27-35`.
  #
  # ## O lote inteiro numa transação (FE-185)
  #
  # No legado cada marcação era uma requisição própria e, quando uma falhava, a
  # tela **ficava fora de sincronia com o servidor**: a linha aparecia marcada e
  # não havia recibo. Aqui é um lote só; falha reverte tudo, e a tela recarrega
  # do servidor em vez de confiar no próprio estado.
  #
  # ## As duas travas no servidor
  #
  # - **D-18** — cobrança `done` (Faturado) recusa qualquer alteração. No legado
  #   isso existia só na tela.
  # - **C1** — recibo de operação de **outro projeto** não entra no lote. É a
  #   mesma família D-01/D-16/D-29/D-76/D-100: no legado, id por parâmetro
  #   descartava o escopo.
  #
  # ## O vínculo dos dois lados, dentro da transação (DB-165)
  #
  # `receipts.operation_id` e `operation.receipt_id` são gravados juntos. No
  # legado eram um `after_create` e um `after_destroy` que faziam
  # `self.operation.save` **sem checar o retorno** — se a operação falhasse na
  # validação, sobrava recibo sem operação apontando de volta.
  class BulkReceiptsService
    class << self
      include ApiResponseHandler

      # `temp_ids` é a lista COMPLETA do que deve ficar no pacote. O que estiver
      # vinculado e não estiver na lista é removido — mesma semântica da lista
      # de tarifas do borderô (DEC-72): a tela manda o estado final, o servidor
      # faz o diff.
      def call(project:, charge_id:, temp_ids:, actor:)
        charge = ::Charge.for_project(project).find_by(id: charge_id) if uuid?(charge_id)
        return { status: 404, error: 'Cobrança não encontrada.' } if charge.nil?
        return billed_error if charge.done?

        unless ReceiptGenerator.remunerations_available?
          return { status: 422, error: ReceiptGenerator::MISSING_REMUNERATION_MODEL }
        end

        desejados = Array(temp_ids).map(&:to_s).uniq
        candidatos = ReceiptGenerator.candidates(project: project, charge: charge)
        return candidatos if candidatos[:status] != 200

        por_temp_id = candidatos[:data].index_by { |c| c[:temp_id] }
        desconhecidos = desejados - por_temp_id.keys
        if desconhecidos.any?
          return { status: 422,
                   error: 'Há operações na seleção que não pertencem a este projeto ou já foram faturadas.',
                   details: { temp_ids: desconhecidos } }
        end

        ActiveRecord::Base.transaction do
          remove_unlisted!(charge, desejados)
          desejados.each { |temp_id| ensure_receipt!(charge, por_temp_id[temp_id], actor) }
          charge.recalculate!
        end

        { status: 200, data: charge.reload }
      rescue ActiveRecord::RecordInvalid => e
        { status: 422, error: e.record.errors.full_messages.to_sentence }
      end

      private

      # **A ORDEM AQUI É OBRIGATÓRIA, e custou um 500 para ficar escrita.**
      #
      # Até a S8 este caminho era **inalcançável**: sem o model `Remuneration`,
      # `BulkReceiptsService` parava no 422 que nomeava a fatia, e nenhum teste
      # chegou a remover um recibo de verdade. Assim que a S8 entregou a
      # remuneração, o primeiro "desmarcar" respondeu **500**:
      #
      #     PG::ForeignKeyViolation: update or delete on table "receipts"
      #     violates foreign key constraint on table "structured_operations"
      #
      # `risk_operations.receipt_id` (S6) e `structured_operations.receipt_id`
      # (S8) têm **FK real** para `receipts`. Destruir o recibo enquanto a
      # operação ainda aponta para ele é o Postgres fazendo exatamente o que a
      # FK existe para fazer — o defeito é a ordem, não a restrição.
      #
      # Então: **solta o lado da operação primeiro, destrói o recibo depois.**
      # Tudo dentro da transação de `call`, que é o que garante que uma falha no
      # meio não deixe operação solta com recibo vivo.
      def remove_unlisted!(charge, desejados)
        charge.receipts.reject { |r| desejados.include?(r.temp_id.to_s) }.each do |receipt|
          operacao = receipt.operation
          # 1) o outro lado do vínculo, com o retorno CHECADO...
          operacao&.update!(receipt_id: nil)
          # 2) ...e só então o recibo, agora sem ninguém referenciando.
          receipt.destroy!
        end
        charge.receipts.reset
      end

      def ensure_receipt!(charge, candidato, actor)
        return if candidato[:persisted]

        operacao = load_operation(candidato)
        raise ActiveRecord::RecordNotFound, 'Operação não encontrada.' if operacao.nil?

        remuneracao = Object.const_get('Remuneration').find(candidato[:remuneration_id])
        montado = ReceiptGenerator.build_attributes(operation: operacao, remuneration: remuneracao, actor: actor)
        raise ActiveRecord::RecordNotFound, montado[:error] if montado[:status] != 200

        receipt = ::Receipt.create!(montado[:data].merge(charge_id: charge.id))
        operacao.update!(receipt_id: receipt.id)
      end

      def load_operation(candidato)
        return nil unless %w[RiskOperation StructuredOperation].include?(candidato[:operation_type])
        return nil unless Object.const_defined?(candidato[:operation_type])

        Object.const_get(candidato[:operation_type]).find_by(id: candidato[:operation_id])
      end

      def billed_error
        { status: 422, error: 'Esta cobrança está Faturada e não aceita mais alteração de recibos.' }
      end

      def uuid?(value)
        value.to_s.match?(ProjectScopedService::UUID_FORMAT)
      end
    end
  end
end

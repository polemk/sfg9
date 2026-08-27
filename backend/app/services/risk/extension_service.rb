# frozen_string_literal: true

module Risk
  # S7 / **BE-277** — a **prorrogação** de vencimento.
  #
  # ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
  #
  # `20220616181724_create_risk_operation_extensions` está entre as **24
  # migrations que nunca subiram** (`analise-dump-producao.md` §1). Nenhuma
  # prorrogação existiu em produção. A fonte é
  # `../sfg/app/models/risk_operation_extension.rb` e
  # `../sfg/app/controllers/pub/risk_operation_extensions_controller.rb`. O
  # golden `M4` trava a leitura dessa fonte, não um comportamento observado.
  #
  # ## O que é replicado
  #
  # - `original_due_date` é carimbado **da operação**, e o valor que vier do
  #   formulário é ignorado (`risk_operation_extension.rb:5`);
  # - o `after_create` sobrescreve `operation.due_date` e salva — o que dispara
  #   o recálculo da cadeia (`BE-265`);
  # - o log é **imutável**: não há `update` nem `destroy` expostos, como no
  #   legado;
  # - a listagem é por `created_at asc` (`extensions_controller.rb:12`).
  #
  # ## O que é novo, e por quê
  #
  # `new_due_date > original_due_date` **no servidor**. No legado só o `minDate`
  # do datepicker impedia; por requisição direta dava para **encurtar** o
  # vencimento, e o `after_create` aplicava a data menor sem reclamar — deixando
  # movimentos legítimos fora da janela de `BE-274`. É a **decisão B-03** pelo
  # caminho que efetivamente encurta prazo. A S5 já pôs o `CHECK` no banco; a
  # validação do model é o que dá mensagem em vez de erro de constraint.
  #
  # **B-03, a outra metade:** encurtar o vencimento deixando movimentos de fora
  # é recusado **com a lista dos movimentos conflitantes**. Como a prorrogação
  # só anda para a frente, esse caso não acontece por aqui — a checagem fica
  # escrita mesmo assim, porque é o único caminho de tela que mexe em `due_date`
  # e porque o dia em que alguém afrouxar a regra acima o teste dirá o que
  # quebrou.
  class ExtensionService
    class << self
      include ApiResponseHandler

      def index(project:, operation_id:)
        operation = Risk::OperationService.find(project, operation_id)
        return not_found_operation if operation.nil?

        { status: 200,
          data: RiskOperationExtension.where(risk_operation_id: operation.id)
                                      .includes(:author).chronological }
      end

      # O drawer "Prorrogar": a data mínima é `due_date + 1` (`:23`).
      def prepare(project:, operation_id:)
        operation = Risk::OperationService.find(project, operation_id)
        return not_found_operation if operation.nil?
        return sem_janela if operation.is_static?

        { status: 200,
          data: { risk_operation_id: operation.id,
                  original_due_date: operation.due_date,
                  min_due_date: operation.due_date + 1,
                  new_due_date: operation.due_date + 1 } }
      end

      def create(project:, operation_id:, attrs:, actor: nil)
        operation = Risk::OperationService.find(project, operation_id)
        return not_found_operation if operation.nil?
        return sem_janela if operation.is_static?

        extensao = RiskOperationExtension.new(
          risk_operation_id: operation.id,
          user_id: actor&.id,
          # Carimbado pelo `before_validation` do model; escrito aqui só para
          # que a validação de presença não dispare antes do callback.
          original_due_date: operation.due_date,
          new_due_date: attrs[:new_due_date],
          observation: attrs[:observation]
        )

        conflitos = movimentos_fora_da_janela(operation, extensao.new_due_date)
        return conflito(conflitos) if conflitos.any?

        RiskOperationExtension.transaction do
          raise ActiveRecord::Rollback unless extensao.save
        end

        return unprocessable(extensao) unless extensao.persisted?

        { status: 201, data: extensao.reload }
      end

      private

      # **B-03.** Movimentos que ficariam fora da janela se o vencimento passasse
      # a ser `nova_data`. Prorrogação só estica, então na prática é vazio — o
      # teste existe para o dia em que alguém afrouxar `must_move_forward`.
      def movimentos_fora_da_janela(operation, nova_data)
        return [] if nova_data.blank?

        data = nova_data.to_date
        return [] if data >= operation.due_date

        RiskMovement.where(risk_operation_id: operation.id)
                    .where('DATE(risk_movements.date) > DATE(?)', data)
                    .order(:date).to_a
      end

      def conflito(movimentos)
        lista = movimentos.map { |m| "#{I18n.l(m.date, format: :default)} (seq. #{m.sequence})" }
        { status: 422,
          error: 'A nova data deixaria movimentos fora da janela da operação: ' \
                 "#{lista.to_sentence}. Exclua ou remaneje esses movimentos antes.",
          details: { movements: movimentos.map(&:id) } }
      end

      def not_found_operation
        { status: 404, error: 'Operação de risco não encontrada.' }
      end

      def sem_janela
        { status: 422, error: 'O par estático do limite não tem vencimento e não é prorrogável.' }
      end

      def unprocessable(record)
        { status: 422, error: record.errors.full_messages.to_sentence, details: record.errors.messages }
      end
    end
  end
end

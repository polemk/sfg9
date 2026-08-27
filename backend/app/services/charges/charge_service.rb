# frozen_string_literal: true

module Charges
  # S6 / **BE-187** — o pacote de cobrança. Dono por **DEC-63**.
  #
  # ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
  #
  # `charges` não existe no banco de produção. Regra espelhada de
  # `../sfg/app/models/charge.rb` e `../sfg/app/controllers/pub/charges_controller.rb`.
  #
  # ## O que muda em relação ao legado
  #
  # - **D-18** — "Faturado" bloqueia **no servidor**. No legado o bloqueio
  #   existia só na tela; a API aceitava a alteração e o pacote fechado mudava.
  # - **D-20** — a lista tinha limite fixo de 1000 **no cliente** e nenhum no
  #   servidor. Agora é Kaminari, aplicado pelo endpoint.
  # - Exclusão bloqueada por recibo responde **422 com a frase nomeando o
  #   vínculo**; o `restrict_with_error` do legado levantava e virava 500.
  # - **Ano em branco** é opção válida no filtro (FE-180): sem ela era
  #   impossível ver todas as cobranças de uma vez.
  class ChargeService < ProjectScopedService
    class << self
      def model = ::Charge
      def resource_label = 'Cobrança'
      def resource_genero = :feminino

      def writable_attributes = %i[date state]

      def base_scope(project)
        model.for_project(project).includes(:author)
      end

      def filter(scope, params)
        scope.in_state(params[:state]).in_month(params[:month]).in_year(params[:year])
      end

      # **D-18 no servidor.** Vale para qualquer escrita, não só para a troca de
      # estado: um pacote faturado é documento emitido.
      def update(project:, id:, attrs:, actor: nil)
        registro = find(project, id)
        return not_found if registro.nil?
        return billed_error if registro.done?

        super
      end

      def destroy(project:, id:)
        registro = find(project, id)
        return not_found if registro.nil?
        return billed_error if registro.done?

        super
      end

      # O extrato da cobrança (FE-182). No legado o `show` tinha um
      # `# TODO #7388 otimizar a busca` no código e montava os totais em Ruby,
      # linha a linha; aqui é **uma consulta agregada** por remuneração.
      #
      # O resultado é idêntico e há teste provando — otimização que muda
      # resultado é defeito (Princípio 9).
      def statement(project:, id:)
        registro = find(project, id)
        return not_found if registro.nil?

        linhas = registro.receipts
                         .group(:kind, :remuneration_id, :title)
                         .pluck(Arel.sql('kind'), Arel.sql('remuneration_id'), Arel.sql('title'),
                                Arel.sql('COUNT(*)'), Arel.sql('SUM(operation_value)'), Arel.sql('SUM(value)'))
                         .map do |kind, remuneration_id, title, total, operacoes, valor|
          { kind: kind, remuneration_id: remuneration_id, title: title,
            receipts_count: total, operations_value: operacoes, value: valor }
        end

        { status: 200, data: { charge: registro, statement: linhas } }
      end

      private

      def billed_error
        { status: 422,
          error: 'Esta cobrança está Faturada e não pode mais ser alterada.',
          details: { state: ['faturada'] } }
      end
    end
  end
end

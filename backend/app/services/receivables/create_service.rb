# frozen_string_literal: true

module Receivables
  # S6 / **BE-151**, **BE-182** — criação do borderô.
  #
  # Borderô e tarifas numa **única transação**, com **um único** recálculo.
  # A sequência e o porquê estão em `Receivables::WriteService`.
  #
  # Corrige, de uma vez:
  #
  # - **D-11** — os dois `save` do controller legado, que faziam a
  #   `RiskOperation` nascer com o líquido **sem as tarifas**;
  # - o `save` de tarifa **não checado** (`receivables_controller.rb:85`): no
  #   legado, uma tarifa que falhasse na validação era silenciosamente
  #   descartada e o borderô ficava gravado com o total errado;
  # - **BE-182** — o `user_id` do corpo era aceito. Aqui é ignorado: o autor é
  #   o da sessão.
  class CreateService < WriteService
    class << self
      def call(project:, attrs:, actor:, taxes: nil)
        erros = validate_references(project, attrs)
        return { status: 422, error: erros.to_sentence, details: { base: erros } } if erros.any?

        entry = ReceivableEntry.new
        resultado = persist(entry: entry, attrs: attrs, taxes_payload: Array(taxes),
                            actor: actor, project: project)
        return resultado if resultado.is_a?(Hash)

        { status: 201, data: resultado }
      end
    end
  end
end

# frozen_string_literal: true

module Receivables
  # S6 / **FE-171**, contrato **C2** — a prévia do formulário.
  #
  # **Não persiste nada.** Nenhuma transação, nenhum `ReceivableEntry`
  # instanciado, nenhum `save`. Monta o **mesmo `Input`** que a gravação monta,
  # chama o **mesmo `Calculator`**, aplica o **mesmo `InputGuard`** e devolve os
  # derivados.
  #
  # É isto que fecha o **D-09** na raiz: no legado a prévia era uma
  # reimplementação **parcial** da fórmula em JavaScript
  # (`../sfg/app/views/pub/receivables/new/_body.js.erb:339-504`) que não
  # calculava `taxa_desconto_nominal_*`, `custo_efetivo_com_float_*`,
  # `multiplicador_*` nem os `*_percent`, e arredondava o total de tarifas de
  # outro jeito. O usuário via um número na tela e outro depois de salvar.
  #
  # Há request spec (tarefa 4.29) que envia **o mesmo payload** para
  # `POST /receivables/preview` e para `POST /receivables` e compara os
  # derivados **campo a campo**. Divergência de um único campo reprova.
  class PreviewService
    class << self
      include ApiResponseHandler

      def call(attrs:, taxes: [], operation_date: nil)
        entrada = build_input(attrs, taxes)

        erros = InputGuard.check(entrada)
        return { status: 422, error: erros.to_sentence, details: { base: erros } } if erros.any?

        resultado = Calculator.call(entrada, iof_rate: IofRate.effective_on(operation_date || Date.current))
        erros = InputGuard.result_errors(resultado)
        return { status: 422, error: erros.to_sentence, details: { base: erros } } if erros.any?

        { status: 200, data: resultado }
      end

      private

      # A montagem do `Input` é a mesma da gravação
      # (`ReceivableEntry#calculator_input`), com uma diferença: aqui as tarifas
      # vêm do payload cru, porque não há registro. Os classificadores são
      # resolvidos a partir do `MovementKind` — **nunca** vindos do cliente:
      # aceitar `is_desagio` do corpo deixaria a tela escolher a base do IOF.
      def build_input(attrs, taxes)
        tipos = MovementKind.where(id: Array(taxes).filter_map { |t| t.symbolize_keys[:movement_kind_id] })
                            .index_by { |k| k.id.to_s }

        Calculator::Input.new(
          **ReceivableEntry::INPUT_COLUMNS.index_with { |c| attrs[c] },
          taxes: Array(taxes).map do |linha|
            dados = linha.symbolize_keys
            tipo = tipos[dados[:movement_kind_id].to_s]
            Calculator::Tax.new(
              value: dados[:value],
              is_advalorem: tipo&.is_advalorem || false,
              is_desagio: tipo&.is_desagio || false,
              is_iof: tipo&.is_iof || false
            )
          end
        )
      end
    end
  end
end

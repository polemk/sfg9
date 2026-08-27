# frozen_string_literal: true

module Sfg
  # Tipo de parâmetro que aceita **só ISO-8601** — o lado servidor do `FE-440`.
  #
  #     optional :from, type: DateTime, coerce_with: Sfg::Iso8601,
  #                     desc: 'Início do período, ISO-8601'
  #
  # **Por que não basta `type: DateTime`.** O coercitor padrão do Grape usa
  # `Date._parse`, que é deliberadamente tolerante: `"31/12/2025"` é aceito e
  # vira 31 de dezembro. Parece inofensivo até alguém mandar `"03/04/2026"` —
  # que o Ruby lê como **3 de abril** e um cliente que pensa em `mm/dd` quis
  # dizer **4 de março**. Nos dois casos a API responde **200** e devolve a
  # janela errada, sem erro nenhum. Num filtro de auditoria isso é uma resposta
  # errada com cara de certa; num filtro de vencimento é dinheiro.
  #
  # O contrato da fronteira é ISO-8601 nos **dois** sentidos: a entity emite
  # `occurred_at` em ISO-8601 UTC, e a entrada recusa qualquer outra forma com
  # **400**. Data em formato de exibição pertence à camada de apresentação.
  class Iso8601
    # `2026-09-14`, `2026-09-14T15:04:05Z`, `2026-09-14T15:04:05-03:00`,
    # com fração de segundo opcional.
    PATTERN = /\A\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?)?\z/

    INVALIDO = 'use ISO-8601 (aaaa-mm-dd ou aaaa-mm-ddThh:mm:ssZ)'

    # É usado como `coerce_with:`, e não como `type:`, porque o Grape confere o
    # valor coagido contra o `type:` declarado — um coercitor que devolvesse
    # `Sfg::Iso8601` não passaria por `DateTime`.
    def self.parse(value)
      return value.to_datetime if value.is_a?(::Time) || value.is_a?(::DateTime)

      texto = value.to_s.strip
      return Grape::Types::InvalidValue.new(INVALIDO) unless texto.match?(PATTERN)

      (::Time.zone.parse(texto)&.to_datetime) || Grape::Types::InvalidValue.new(INVALIDO)
    rescue ArgumentError
      Grape::Types::InvalidValue.new(INVALIDO)
    end

    def self.call(value) = parse(value)
  end
end

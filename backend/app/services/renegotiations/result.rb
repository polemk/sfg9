# frozen_string_literal: true

module Renegotiations
  # S9 — **uma forma de resposta para toda a fatia**.
  #
  # A base tem duas convenções vivas: `ApiResponseHandler`, que devolve
  # `{success:, data:, status:}`, e `ProjectScopedService`, que devolve
  # `{status:, data:, error:, details:}`. As duas são legítimas e as duas ficam.
  #
  # O que **não** pode acontecer é uma fatia usar as duas: o endpoint testaria
  # `resultado[:success]` num serviço e `resultado[:status] != 200` no outro, e o
  # primeiro serviço que trocasse de forma passaria a responder 200 com corpo de
  # erro sem que nada quebrasse. Como **todos** os serviços de S9 são escopados
  # por projeto, a fatia inteira fala a língua do `ProjectScopedService`.
  module Result
    def ok(data, status: 200)
      { status: status, data: data }
    end

    def created(data)
      { status: 201, data: data }
    end

    def unprocessable(message, details: nil)
      resposta = { status: 422, error: message }
      resposta[:details] = details if details
      resposta
    end

    def forbidden(message)
      { status: 403, error: message, code: 'FORBIDDEN' }
    end

    def not_found_result(message)
      { status: 404, error: message }
    end

    def from_record_invalid(error)
      unprocessable(error.record.errors.full_messages.to_sentence, details: error.record.errors.messages)
    end
  end
end

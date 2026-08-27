# frozen_string_literal: true

module Receivables
  # S6 / **BE-152** — edição do borderô.
  #
  # Duas regras que valem a pena ler antes de mexer:
  #
  # 1. **Payload sem a chave `taxes` PRESERVA as tarifas existentes** (tarefa
  #    2.23). Um `PUT` que só corrige a descrição não pode apagar a lista de
  #    tarifas por omissão. Com a chave presente — inclusive vazia — a lista
  #    passa a ser a enviada, e o que saiu é apagado: é a exclusão pendente da
  #    **DEC-72**.
  # 2. **O tipo de operação é imutável na edição** (FE-165). Trocar o subtipo de
  #    um borderô já lançado moveria exposição entre limites sem deixar rastro
  #    na operação de risco. No legado o campo era editável e nada acontecia
  #    além de a operação trocar de tipo em silêncio.
  #
  # O escopo por projeto é aplicado **na busca** (`find`), nunca por
  # `default_scope`: id de outro projeto simplesmente não é encontrado, e a
  # resposta é a **mesma** de um id inexistente (404).
  class UpdateService < WriteService
    class << self
      def call(project:, id:, attrs:, actor:, taxes: :unchanged)
        entry = find(project, id)
        return not_found if entry.nil?

        atributos = attrs.except(:risk_operation_subtype_id, :risk_operation_type_id)
        erros = validate_references(project, atributos)
        return { status: 422, error: erros.to_sentence, details: { base: erros } } if erros.any?

        payload = taxes == :unchanged ? nil : Array(taxes)
        resultado = persist(entry: entry, attrs: atributos, taxes_payload: payload,
                            actor: actor, project: project)
        return resultado if resultado.is_a?(Hash)

        { status: 200, data: resultado }
      end

      def find(project, id)
        return nil unless uuid?(id)

        ReceivableEntry.for_project(project).find_by(id: id)
      end
    end
  end
end

# frozen_string_literal: true

module Structured
  # S8 / **BE-296**…**BE-299** — os **tipos de operação estruturada**.
  #
  # Catálogo **GLOBAL** (contrato C1, regra 4): herda de `CatalogService`, que
  # não chama `current_project!` em método nenhum. Um tipo vale para todos os
  # projetos, e escondê-lo por projeto quebraria a remuneração que já aponta
  # para ele.
  #
  # ## Quatro defeitos que somem por herdar o molde
  #
  # 1. **`where('is_active = 1 ')`** — SQL literal, com o espaço sobrando
  #    (`structured_operation_type.rb:2`). O `scope :active` do `GlobalCatalog`
  #    é bind + boolean.
  # 2. **`.limit().offset()` sem `!`** — no Grape do legado eles eram
  #    **descartados** e a lista voltava inteira (D-20). O `paginate` do
  #    `ControllerHelpers` aplica Kaminari de verdade e emite o total real.
  # 3. **`integration_key` derivada a cada save** — aqui é `on: :create` e
  #    **congelada** depois (BE-298): a chave é contrato de integração, e
  #    recalculá-la em silêncio quebra consumidor externo.
  # 4. **`destroy` em objeto não persistido** — o controller legado chamava
  #    `destroy` num `new` quando o create falhava. Some com o molde.
  #
  # ## BE-296 — o filtro de ativo passa a ser OPCIONAL, e isso é correção
  #
  # No legado a listagem era sempre `.active`. Consequência: desativar um tipo
  # o fazia **desaparecer da tela de administração**, e não havia como
  # reativá-lo pela UI — só por SQL. Aqui `?active=true` filtra e a ausência do
  # parâmetro mostra tudo.
  #
  # ## BE-299 — uma guarda, não duas
  #
  # O legado tinha a checagem de `is_default` **duas vezes** (no controller e no
  # `before_destroy`) e nenhuma de uso — e ainda assim respondia **200**, por
  # causa do ternário degenerado `errors.any? ? :ok : :ok`. Aqui a guarda de
  # `is_default` mora no model, a de uso vem de `blocking_dependents`, e as duas
  # devolvem **422 com a frase**. Como os **quatro** tipos semeados são
  # `is_default`, na prática nenhum é removível — replicado, dizendo por quê.
  class OperationTypeService < CatalogService
    class << self
      def model = ::StructuredOperationType
      def resource_label = 'Tipo de operação estruturada'

      # Os três flags entram no `writable` porque estão no `permit` do legado
      # (`structured_operation_types_controller.rb:133-136`) — **sem formulário
      # e sem um único consumidor** (Q-R15). São migrados como coluna e não
      # ganham leitor; o spec documenta a ausência.
      #
      # `is_default` **não** entra: quem a marca é o seed, e deixá-la editável
      # daria ao usuário o botão de destravar a própria guarda de exclusão.
      def writable_attributes
        %i[title integration_key is_active allow_manual_operations allow_receivable_entries has_pre_faturamento]
      end

      # BE-298 — a imutabilidade que a UI promete passa a valer no SERVIDOR.
      # `title` é `readonly` no formulário do legado e mesmo assim viajava no
      # `permit`; `integration_key` idem. Aqui os dois são recusados na edição,
      # com a frase dizendo por quê.
      IMMUTABLE_ON_UPDATE = %i[title integration_key].freeze

      TITLE_IMMUTABLE = 'O título e a chave de integração de um tipo de operação estruturada não podem ' \
                        'ser alterados: a chave é contrato com integrações externas e o título é o que ' \
                        'as remunerações já emitidas copiaram.'

      def update(id:, attrs:, actor: nil)
        return { status: 422, error: TITLE_IMMUTABLE } if attrs.keys.intersect?(IMMUTABLE_ON_UPDATE)

        super
      end
    end
  end
end

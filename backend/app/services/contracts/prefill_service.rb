# frozen_string_literal: true

module Contracts
  # S12 / BE-338 — o que a tela de "nova versão" recebe já preenchido.
  #
  # O legado tinha `generate_new_version` (`contract.rb:31-39`) fazendo
  # `where(kind:).last.version + 1` **sem guarda**: no primeiro contrato de um
  # tipo, `where(...).last` é `nil` e a chamada estourava `NoMethodError`. Ou
  # seja, a única situação em que a tela era realmente necessária — não existe
  # nenhuma versão ainda — era a única em que ela quebrava.
  #
  # Aqui o primeiro contrato de um tipo **abre vazio**, com `next_version = 1`.
  module PrefillService
    module_function

    def call(kind_or_slug)
      kind = Contract.kind_for(kind_or_slug)
      return nil if kind.blank?

      anterior = Resolver.current(kind)

      {
        kind: kind,
        slug: Contract::SLUGS.fetch(kind, kind.parameterize),
        next_version: (anterior&.version || 0) + 1,
        title: anterior&.title.to_s,
        description_html: anterior ? anterior.description_html : '',
        previous_version: anterior&.version,
        previous_id: anterior&.id,
        # Mitigação 2 da DEC-80, entregue já no prefill: quem vai publicar vê,
        # ANTES de escrever, quantos aceites a versão atual carrega.
        current_accepted_count: anterior ? anterior.contract_deals.count : 0
      }
    end
  end
end

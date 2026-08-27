# frozen_string_literal: true

module Contracts
  # S12 / BE-331 — **qual é o contrato vigente de um tipo**.
  #
  # Resposta: o de **maior `version`**. O legado usava
  # `Contract.where("kind ILIKE ?", type).last` (`pub/contracts_controller.rb:4`),
  # que ordena por `id`: re-salvar uma versão antiga a movia para o fim da tabela
  # e o público passava a ler o texto errado. Nada na tela denunciava isso.
  #
  # E `nil.kind` na linha seguinte transformava tipo inexistente em **500**.
  # Aqui, tipo desconhecido é `nil` e vira 404 no endpoint.
  module Resolver
    module_function

    # Aceita o tipo pela string literal (`Termos de Uso`) ou pelo slug
    # (`termos-de-uso`) — Q-B34 resolvida nas duas pontas.
    def current(kind_or_slug)
      kind = Contract.kind_for(kind_or_slug)
      return nil if kind.blank?

      Contract.of_kind(kind).newest_first.first
    end

    def current!(kind_or_slug)
      current(kind_or_slug) or raise ActiveRecord::RecordNotFound
    end

    # Uma linha por tipo, com a versão mais recente de cada um.
    def current_all
      Contract.current_per_kind.to_a
    end

    # Os tipos que já têm ao menos uma versão publicada. É o que a rota pública
    # sem tipo devolve, em vez do 500 que o legado dava sempre (BE-349).
    def available_kinds
      Contract.distinct.pluck(:kind).sort_by { |k| Contract::KINDS.index(k) || 99 }
    end

    def history(kind_or_slug)
      kind = Contract.kind_for(kind_or_slug)
      return Contract.none if kind.blank?

      Contract.of_kind(kind).newest_first
    end
  end
end

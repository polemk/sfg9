# frozen_string_literal: true

module Api
  module Entities
    # S12 / DB-331 — o aceite, do ponto de vista de quem aceitou.
    #
    # **`accepted_body` NÃO é exposto aqui.** O texto integral sai pelo
    # exportador de prova (`OPS-333`), que é de quem administra; a tela do perfil
    # precisa saber *que* aceitou, *qual versão* e *quando* — o documento
    # completo ela lê na página do contrato.
    class ContractDeal < Grape::Entity
      expose :id
      expose :contract_id
      expose :contract_kind, as: :kind
      expose :contract_version, as: :version
      expose :accepted_at
      # DEC-66: a interface precisa distinguir "eu aceitei" de "a base antiga
      # carimbou por mim". Esconder isso reproduziria exatamente a indistinção
      # que a decisão existe para acabar.
      expose :source
      expose :legacy_accepted_at
      expose :hash_matches_current do |d|
        d.hash_matches_current?
      end
    end
  end
end

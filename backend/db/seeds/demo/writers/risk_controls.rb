# frozen_string_literal: true

module Demo
  module Writers
    # A matriz de limites (`risk_controls`). Chave natural:
    # `(company_id, carrier_id, risk_operation_type_id)` — o índice único da S5.
    #
    # **Grava `limite`/`taxa` e deixa as 8 colunas pré-2022 nulas.** As
    # `limite_auto_liquidaveis` / `taxa_fomento` e companhia sobrevivem na
    # migration por paridade (DB-240/DB-572), mas escrever nas duas gerações de
    # coluna ao mesmo tempo é ensinar a base a ter duas verdades sobre o mesmo
    # limite — e a próxima pessoa não saberá qual delas a tela lê.
    #
    # As 4 modalidades são **linhas** de `risk_operation_types`, e são dado de
    # REFERÊNCIA (OPS-230): quem as escreve é `Seeds::Reference::RiskOperationTypes`,
    # aplicado pelo `scaffolding`. Aqui elas são apenas **resolvidas** pela chave
    # de integração.
    #
    # Este módulo já teve lista própria, com as flags copiadas à mão — e elas
    # divergiam da referência em duas das quatro linhas (`fomento` nascia com
    # `has_pre_faturamento`, `comissária` sem). A flag é `create_only` no seed de
    # referência e decide se o limite abre par estático: a divergência não
    # aparecia como erro, aparecia como operação estática no tipo errado. Duas
    # listas para o mesmo catálogo é sempre isso.
    class RiskControls < Base
      def self.requires = %w[RiskControl RiskOperationType]
      def self.owner_slice = 'S5'

      # As quatro chaves são CONTRATO com o ETL (S14) e com a referência.
      MODALITY_KEYS = %w[fomento comissaria intercompany auto_liquidavel].freeze

      def call
        types = resolve_operation_types!

        ledger.controls.each do |control|
          company = companies_by_key[control.company.key]
          carrier = carrier_for(control.carrier)
          type = types[control.modality]
          next if company.nil? || carrier.nil? || type.nil?

          upsert!(::RiskControl,
                  find_by: { company_id: company.id, carrier_id: carrier.id,
                             risk_operation_type_id: type.id },
                  attributes: {
                    project_id: company.project_id,
                    # O legado reescreve `title` com o título do carrier a cada
                    # gravação. Replicado (DEC-30).
                    title: control.carrier.title,
                    limite: control.limite,
                    taxa: control.taxa,
                    is_active: true,
                    has_safegold_management: true
                  })
        end
      end

      private

      # Pela CHAVE, nunca pelo título: o título é editável na tela e a chave é
      # congelada (DC-22).
      def resolve_operation_types!
        found = ::RiskOperationType.where(integration_key: MODALITY_KEYS).index_by(&:integration_key)
        missing = MODALITY_KEYS - found.keys
        raise "Tipos de limite ausentes: #{missing.join(', ')} — rode `rake reference:seed`" if missing.any?

        found.transform_keys(&:to_sym)
      end
    end
  end
end

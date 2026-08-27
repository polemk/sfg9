# frozen_string_literal: true

module Demo
  module Writers
    # As empresas do grupo. Chave natural: `(project_id, title)` — o índice único
    # composto que a S4 declara (DB-555).
    #
    # O CNPJ de cada uma compartilha a **raiz de 8 dígitos** do grupo e varia só o
    # número de ordem da filial, com o dígito verificador recalculado. É como
    # funciona no cadastro real, e é o detalhe que faz a tela parecer um sistema
    # em produção em vez de um ambiente de teste.
    class Companies < Base
      def self.requires = %w[Company]
      def self.owner_slice = 'S4'

      def call
        ledger.companies.each do |company|
          project = project_for(company.client)
          next if project.nil?

          upsert!(::Company,
                  find_by: { project_id: project.id, title: company.title },
                  attributes: {
                    cnpj: company.cnpj,
                    document: company.cnpj,
                    document_type: 'cnpj',
                    has_safegold_management: true
                  })
        end
      end
    end
  end
end

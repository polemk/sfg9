# frozen_string_literal: true

module Demo
  module Writers
    # Os fornecedores de cada cliente. Chave natural: `(project_id, title)`.
    #
    # **Por que este módulo existe.** A renegociação da S9 exige `provider_id`
    # (`null: false`) e carimba `provider_name` a partir de `provider.title` em
    # toda gravação — não há renegociação sem fornecedor cadastrado. Antes disto
    # o escritor de renegociações tentava gravar sem fornecedor nenhum e falhava
    # inteiro; era o pedaço da cadeia que faltava.
    #
    # **Fornecedor é escopado por projeto (C1)**, não é catálogo global: o mesmo
    # nome vira uma linha por cliente que o usa, exatamente como no cadastro
    # real, e cada uma com CNPJ próprio de dígito verificador válido — a tela de
    # fornecedores valida o documento, e uma demonstração que recusa o próprio
    # dado é constrangedora.
    class Providers < Base
      def self.requires = %w[Provider]
      def self.owner_slice = 'S4'

      def call
        ledger.providers.each do |provider|
          project = project_for(provider.client)
          next if project.nil?

          upsert!(::Provider,
                  find_by: { project_id: project.id, title: provider.title },
                  attributes: {
                    document: provider.cnpj,
                    # **`'CNPJ'`, em caixa alta**: o conjunto é fechado
                    # (`Sfg::Document::TYPES`) e o model não normaliza a caixa.
                    # Com `'cnpj'` minúsculo a validação passava (o normalizador
                    # da gravação corrigia), mas o escritor propunha um valor
                    # diferente do gravado em toda execução — 75 fornecedores
                    # "atualizados" por rodada, sem uma única mudança real.
                    document_type: 'CNPJ',
                    legal_name: provider.title,
                    city: provider.city,
                    state: provider.uf,
                    is_active: true
                  })
        end
      end
    end
  end
end

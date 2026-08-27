# frozen_string_literal: true

module Seeds
  module Reference
    # S6 / **OPS-153**, **DB-560** — os tipos de recebível. REFERÊNCIA.
    #
    # `receivable_entries.receivable_kind_id` é obrigatório: sem uma linha aqui,
    # nenhum borderô pode ser lançado.
    #
    # ## As 7 linhas são as de PRODUÇÃO — a tarefa F.9 falava em 5
    #
    # F.9 listava **5**: Cheque, Duplicata, **"Cartão de crédito"**, ACC, PAC.
    # No dump são **7**, e o quinto se chama **"Cartão"**, não "Cartão de
    # crédito". Os dois que faltavam no mapa são **Vale refeição** e
    # **Intercompany** (este criado em 04/2023). Divergência registrada no
    # relatório.
    class ReceivableKinds < Catalog
      ENTRIES = [
        { legacy_id: 1, title: 'Duplicata' },
        { legacy_id: 2, title: 'Cheque' },
        { legacy_id: 3, title: 'ACC' },
        { legacy_id: 4, title: 'PAC' },
        { legacy_id: 5, title: 'Cartão' },
        { legacy_id: 6, title: 'Vale refeição' },
        { legacy_id: 7, title: 'Intercompany' }
      ].freeze

      class << self
        def catalog_name = 'Tipos de recebível (OPS-153)'
        def model = ::ReceivableKind
        def natural_key = %i[legacy_id]

        def entries
          ENTRIES.map do |entry|
            { legacy_id: entry[:legacy_id], title: entry[:title],
              integration_key: GlobalCatalog.slugify(entry[:title]), is_active: true }
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module Seeds
  module Reference
    # S6 / **OPS-153**, **DB-559** — as carteiras. Dado de REFERÊNCIA.
    #
    # **Por que é referência e não vitrine:** `receivable_entries.wallet_id` é
    # obrigatório. Sem uma linha aqui, o formulário de borderô sobe com o select
    # vazio e **nenhum borderô pode ser lançado** no primeiro boot. No legado a
    # flag `should_seed_*` vinha `false` e este seed **nunca rodava**
    # (`../sfg/db/seeds.rb`).
    #
    # ## As 12 linhas são as de PRODUÇÃO, medidas — não as 10 do mapa
    #
    # A tarefa 1.17 e a F.8 listavam **10** carteiras: ACC, ACE, Antecipação,
    # **Caução**, Cheque, Comissária, Conta Garantida, Desconto, **Domicílio**,
    # Fomento. Contei no dump de 31/05/2025: são **12**, e nem "Caução" nem
    # "Domicílio" existem. O que existe, e o mapa não tinha, é **Risco Sacado**,
    # **Pré-faturamento**, **Boleto Escrow** e **Intercompany** — as quatro
    # criadas por usuários reais entre 2022 e 2023.
    #
    # A DEC-30 diz que o legado é o sistema validado. O sistema validado é o que
    # **rodou**, e o que rodou tem estas 12. A divergência está registrada no
    # relatório da S6.
    #
    # ## `legacy_id` é o id de PRODUÇÃO, e é contrato com o ETL
    #
    # É por ele que o conversor (S14/S6) reencontra a carteira em vez de criar
    # uma segunda "Fomento". A produção também tem um `legacy_id` próprio, que
    # aponta para o Django de 2021 — esse não viaja: aqui a origem é a base
    # Rails, que é de onde a carga sai.
    #
    # `"Boleto Escrow "` tem **espaço no fim** em produção. O
    # `normalize_catalog_title` do `GlobalCatalog` faz `strip`, então a linha
    # nasce sem ele — e o ETL reencontra por `legacy_id`, não por título, de
    # propósito.
    class Wallets < Catalog
      ENTRIES = [
        { legacy_id: 1, title: 'Antecipação' },
        { legacy_id: 2, title: 'ACE' },
        { legacy_id: 3, title: 'Desconto' },
        { legacy_id: 4, title: 'Fomento' },
        { legacy_id: 5, title: 'ACC' },
        { legacy_id: 6, title: 'Cheque' },
        { legacy_id: 7, title: 'Conta Garantida' },
        { legacy_id: 8, title: 'Comissária' },
        { legacy_id: 9, title: 'Risco Sacado' },
        { legacy_id: 10, title: 'Pré-faturamento' },
        { legacy_id: 11, title: 'Boleto Escrow' },
        { legacy_id: 12, title: 'Intercompany' }
      ].freeze

      class << self
        def catalog_name = 'Carteiras (OPS-153)'
        def model = ::Wallet
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

# frozen_string_literal: true

module Seeds
  module Reference
    # **DONA: S8** (`DB-293`). Semeado pela S6 por dependência: sem uma linha
    # aqui, o formulário de borderô sobe com o select de fonte de recurso vazio
    # e **nenhum borderô pode ser lançado** — `resource_source_id` é obrigatório
    # e está preenchido em 28.131 de 28.131 linhas de produção.
    #
    # ## S8: as 6 linhas são as de PRODUÇÃO, e divergem do seu mapa
    #
    # A tarefa 2.2 da S8 lista **7**: Caixa, Comissária, Defasagem, Fomento,
    # Garantia, Recompra, Retenção. No dump são **6**: Caixa, Garantia,
    # Comissaria (**sem acento**), Fomento, Recompra e **13º salário**. Não há
    # "Defasagem" nem "Retenção".
    #
    # ## A chave `13?_salario` é PRESERVADA, e não é erro de digitação
    #
    # `I18n.transliterate("13º salário")` produz `13? salario` — o `º` não tem
    # equivalente ASCII na tabela do Rails —, e o `gsub(" ","_")` do legado fecha
    # em `13?_salario`. É a chave que está em produção. O `slugify` do ai9
    # produziria `13_salario`, que é mais bonito e **é outra chave**: mudar a
    # forma de uma chave de integração quebra consumidor externo em silêncio
    # (mesma leitura do DEC-85 e do DC-22). Fica como está, e a decisão de
    # normalizá-la é da S8, com o usuário.
    class ResourceSources < Catalog
      ENTRIES = [
        { legacy_id: 1, title: 'Caixa',       key: 'caixa' },
        { legacy_id: 2, title: 'Garantia',    key: 'garantia' },
        { legacy_id: 3, title: 'Comissaria',  key: 'comissaria' },
        { legacy_id: 4, title: 'Fomento',     key: 'fomento' },
        { legacy_id: 5, title: 'Recompra',    key: 'recompra' },
        { legacy_id: 6, title: '13º salário', key: '13?_salario' }
      ].freeze

      class << self
        def catalog_name = 'Fontes de recurso (DB-293 — dona: S8)'
        def model = ::ResourceSource
        def natural_key = %i[legacy_id]

        def entries
          ENTRIES.map do |e|
            { legacy_id: e[:legacy_id], title: e[:title], integration_key: e[:key], is_active: true }
          end
        end
      end
    end
  end
end

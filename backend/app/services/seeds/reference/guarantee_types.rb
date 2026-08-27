# frozen_string_literal: true

module Seeds
  module Reference
    # S3 / **DB-558, DEC-86** — os tipos de garantia, semeados como
    # **PROVISÓRIOS**.
    #
    # **Por que este catálogo é de REFERÊNCIA e não de demonstração:** sem
    # nenhuma linha aqui, a tela de garantias do projeto (S4) sobe com o select
    # **vazio** e ninguém consegue cadastrar garantia nenhuma. Isso não é falta
    # de dado de vitrine, é o sistema não funcionar no primeiro boot — que é a
    # definição de dado de referência.
    #
    # **É exatamente o defeito do legado.** A tabela existe lá desde 2022
    # (`20220627125208_create_project_guarantee_types.rb`), o select é alimentado
    # por `ProjectGuaranteeType.all`, há item de menu — e **nenhum seed a
    # popula**. Zero ocorrências de "guarantee" em `db/seeds.rb`, nada em
    # `db/factories/`. O select sobe vazio até alguém cadastrar à mão.
    #
    # **Não há nada a migrar: o conteúdo é NOVO.** Os oito tipos abaixo são
    # suposição do orquestrador — os instrumentos de garantia usuais em operação
    # de crédito — e nascem marcados `is_provisional: true` para que a tela possa
    # dizer isso ao usuário em vez de ele descobrir depois. **A lista definitiva
    # é do cliente**, e substituí-la é trocar estas linhas: sem migration, sem
    # deploy de código.
    #
    # **Fronteira com a S20:** o escritor `Demo::Writers::GuaranteeTypes` grava
    # os MESMOS títulos, por `find_by(title:)`. Como a chave natural é a mesma,
    # os dois seeds convergem para as mesmas oito linhas — não duplicam. Se
    # alguém mexer nesta lista, `db/seeds/demo/ledger/ancillary.rb`
    # (`GUARANTEE_TYPES`) tem de mudar junto, e vice-versa.
    class GuaranteeTypes < Catalog
      NOTE = 'Tipo provisório do seed de demonstração (DEC-86) — a lista definitiva é do cliente.'

      # Os mesmos oito títulos de `Demo::Ledger::Ancillary::GUARANTEE_TYPES`.
      TITLES = [
        'Aval',
        'Nota Promissória',
        'Penhor Mercantil',
        'Alienação Fiduciária',
        'Cessão Fiduciária de Recebíveis',
        'Fiança Bancária',
        'Hipoteca',
        'Seguro Garantia'
      ].freeze

      class << self
        def catalog_name = 'Tipos de garantia (DEC-86 — provisórios)'
        def model = ::ProjectGuaranteeType

        def entries
          TITLES.each_with_index.map do |title, index|
            {
              title: title,
              integration_key: GlobalCatalog.slugify(title),
              is_active: true,
              is_provisional: true,
              sort_order: index + 1,
              description: NOTE,
              observation: NOTE
            }
          end
        end
      end
    end
  end
end

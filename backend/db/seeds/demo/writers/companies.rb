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

          # **`cnpj`, `document` e `document_type` SAIRAM daqui.**
          #
          # Eles nunca existiram: nem em `companies` do ai9 (a tabela tem
          # `project_id`, `title`, `legacy_id` e `has_safegold_management`), nem
          # no legado — `20210510211117_create_companies.rb` cria `project_id` e
          # `title`, e nenhuma migration acrescenta coluna depois. A tela não
          # mostra documento de empresa e a entity não o expõe.
          #
          # Os três nomes para a mesma ideia entregam o que aconteceu: foi chute
          # de qual seria o nome da coluna, sem abrir o schema.
          #
          # O mecanismo do orquestrador fez a coisa certa — ignorou e avisou.
          # Mas o aviso dele é "coluna **ainda** inexistente", que promete uma
          # fatia dona que vai entregar. Aqui não vinha ninguém, e o recado
          # ficava na tela de quem instala, a cada `rake demo:seed`, sugerindo
          # pendência onde não há.
          #
          # A contraparte tomadora do Safegold é identificada por razão social
          # dentro do projeto — há índice único em `(project_id, title)`. Quem
          # tem documento no sistema é o FORNECEDOR (`providers.document`), e lá
          # o seed grava de verdade.
          upsert!(::Company,
                  find_by: { project_id: project.id, title: company.title },
                  attributes: { has_safegold_management: true })
        end
      end
    end
  end
end

# frozen_string_literal: true

module Seeds
  module Reference
    # S3 / **OPS-540** — **o carregador único** dos seeds de referência.
    #
    # O que esta classe resolve: antes dela, `db/seeds.rb` fazia dois `load` de
    # caminho fixo, e cada fatia nova acrescentaria o seu — até o deploy ter
    # cinco formas de semear e nenhuma saber dizer se rodou. Aqui a lista é
    # **dado**, a execução é **idempotente**, e o relatório diz o que aconteceu
    # em cada catálogo.
    #
    # **Aplicado pelo deploy:** `rake reference:seed` (ver
    # `lib/tasks/reference.rake`). Roda em qualquer ambiente, inclusive
    # produção, e rodar duas vezes não muda nada — é essa a propriedade que o
    # torna seguro de pôr no passo de deploy.
    #
    # **Catálogo cuja fatia dona ainda não entregou o model é PULADO com aviso**,
    # nomeando o model e a fatia. É o mesmo contrato dos escritores do seed de
    # demonstração (`db/seeds/demo/writers/base.rb`): a linha pode ser declarada
    # antes de a tabela existir, e passa a valer sozinha quando ela nascer.
    #
    # ### Fronteira: referência × demonstração
    #
    # | | referência (aqui) | demonstração (S20, `db/seeds/demo/`) |
    # | - | - | - |
    # | o que é | dado sem o qual o sistema não sobe | dado de vitrine |
    # | quando roda | **todo** deploy, todo ambiente | só quando se quer a demo |
    # | exemplo | papéis, permissões, tipos de garantia | portadores, empresas, borderôs |
    #
    # No legado os dois estavam misturados, a ponto de o bloco de empresas estar
    # marcado no próprio código como "seed feito somente para vídeo de aprovação".
    module Runner
      # A ordem é dependência, não estética.
      CATALOGS = [
        { seeder: 'Seeds::Reference::UserTypes',
          label: 'Papéis do Safegold (DEC-41)', requires: %w[UserType], slice: 'S0' },
        { seeder: 'Seeds::Reference::Permissions',
          label: 'Catálogo de permissões (DEC-108)', requires: %w[Permission], slice: 'S0' },
        { seeder: 'Seeds::Reference::GuaranteeTypes',
          label: 'Tipos de garantia (DEC-86 — provisórios)', requires: %w[ProjectGuaranteeType], slice: 'S3' },
        # S12 / OPS-330. Publica a **versão 1** de cada tipo de contrato e
        # **NÃO gera nenhum aceite** — o oposto do seed do legado, que re-salvava
        # todos os usuários e fabricava aceite retroativo para a base inteira
        # (`db/seeds.rb:141-157`). É dado de referência e não de vitrine: sem os
        # Termos publicados, o banner de aceite não tem o que pedir.
        { seeder: 'Seeds::Reference::Contracts',
          label: 'Contratos — ToU e Privacidade (OPS-330)', requires: %w[Contract], slice: 'S12' },
        # S5 / OPS-230 e OPS-231. Sem os quatro tipos de limite nenhum
        # `RiskControl` pode ser criado (o tipo é obrigatório) e o console de
        # risco sobe sem cabeçalho; sem os oito tipos de movimentação a S7 não
        # consegue lançar movimento nenhum — três deles são resolvidos POR CHAVE
        # pelo próprio sistema (B-09).
        { seeder: 'Seeds::Reference::RiskOperationTypes',
          label: 'Tipos de limite de risco (OPS-230)', requires: %w[RiskOperationType], slice: 'S5' },
        { seeder: 'Seeds::Reference::RiskMovementTypes',
          label: 'Movimentações de risco (OPS-231)', requires: %w[RiskMovementType], slice: 'S5' },
        # S6 / OPS-153. Os três catálogos do borderô são REFERÊNCIA pelo mesmo
        # critério dos de cima: `wallet_id`, `receivable_kind_id` e
        # `resource_source_id` são **obrigatórios** em `receivable_entries`, e
        # sem tarifa não há deságio, não há IOF e o CET sai zero. Sem estas
        # linhas nenhum borderô pode ser lançado no primeiro boot.
        #
        # No legado o seed existia e **nunca rodava**: as flags `should_seed_*`
        # vinham `false` (`../sfg/db/seeds.rb`).
        #
        # `ResourceSources` é da **S8** (DB-293) e é semeada aqui por
        # dependência — a tabela nasceu na S6 pelo mesmo motivo (FK obrigatória
        # de `receivable_entries`). Está escrito no cabeçalho do arquivo.
        { seeder: 'Seeds::Reference::Wallets',
          label: 'Carteiras (OPS-153)', requires: %w[Wallet], slice: 'S6' },
        { seeder: 'Seeds::Reference::ReceivableKinds',
          label: 'Tipos de recebível (OPS-153)', requires: %w[ReceivableKind], slice: 'S6' },
        { seeder: 'Seeds::Reference::MovementKinds',
          label: 'Tipos de movimentação (OPS-153)', requires: %w[MovementKind], slice: 'S6' },
        { seeder: 'Seeds::Reference::ResourceSources',
          label: 'Fontes de recurso (DB-293 — dona: S8)', requires: %w[ResourceSource], slice: 'S6' },
        # BE-160 / D-15 — sem a linha de alíquota o calculador cai no valor
        # cravado de origem. Hoje dá no mesmo; no dia em que a alíquota mudar,
        # não daria, e o recálculo histórico usaria a de hoje em silêncio.
        { seeder: 'Seeds::Reference::IofRates',
          label: 'Alíquota de IOF (BE-160)', requires: %w[IofRate], slice: 'S6' },
        # S8 / DB-292. Os quatro tipos de operação estruturada. Entram pelo
        # mesmo critério dos tipos de limite da S5: sem uma linha aqui,
        # `Remuneration` não tem tipo da classe **EST** a que apontar e
        # `Receipt#fetch` nunca acha taxa para operação estruturada — o
        # faturamento desse lado sai zerado, em silêncio.
        #
        # `resource_kinds` **não tem linha aqui, e isso é decisão medida**: o
        # portão T-D7 abriu com zero (0 linhas na tabela, 0 de 28.131
        # `receivable_entries` com `resource_kind_id`) e os 10 IDs estão
        # `dropped` com a evidência. Não crie a linha nem a tabela.
        { seeder: 'Seeds::Reference::StructuredOperationTypes',
          label: 'Tipos de operação estruturada (DB-292)',
          requires: %w[StructuredOperationType], slice: 'S8' }
        # S17: acrescentem a linha do catálogo de vocês aqui, com
        # um arquivo em `app/services/seeds/reference/` herdando de
        # `Seeds::Reference::Catalog`. Não inventem um segundo mecanismo.
      ].freeze

      module_function

      def call!(io: nil)
        io&.puts('🌱 Seeds de REFERÊNCIA (idempotentes — rodar de novo não muda nada)')

        CATALOGS.map do |entry|
          faltando = missing_models(entry)
          if faltando.any?
            report = Report.skipped(entry[:label],
                                    "#{faltando.join(', ')} ainda não existe (chega na #{entry[:slice]})")
            io&.puts("   #{report}")
            next report
          end

          run_one(entry, io)
        end
      end

      # Roda UM catálogo, pelo nome do semeador. É o que os pontos de entrada
      # individuais de `db/seeds/reference/*.rb` chamam — eles existem porque o
      # `parity-ledger` aponta para cada arquivo, e continuam sendo casca fina
      # sobre este mesmo carregador. Nenhuma lógica duplicada.
      def call_one!(seeder_name, io: nil)
        entry = CATALOGS.find { |c| c[:seeder] == seeder_name }
        raise ArgumentError, "Catálogo desconhecido: #{seeder_name}" if entry.nil?

        faltando = missing_models(entry)
        if faltando.any?
          report = Report.skipped(entry[:label], "#{faltando.join(', ')} ainda não existe (chega na #{entry[:slice]})")
          io&.puts("   #{report}")
          return report
        end

        run_one(entry, io)
      end

      # Só olha: não escreve nada.
      def status(io: $stdout)
        CATALOGS.each do |entry|
          faltando = missing_models(entry)
          io.puts(faltando.empty? ? "   ✔ #{entry[:label]}" : "   ⏭ #{entry[:label]} — aguarda #{faltando.join(', ')} (#{entry[:slice]})")
        end
      end

      def run_one(entry, io)
        seeder = entry[:seeder].constantize
        resultado = invoke(seeder, io)
        return resultado if resultado.is_a?(Report)

        # Semeador legado da S0 (`UserTypes`, `Permissions`): devolve a coleção,
        # não um relatório. Conta as linhas e diz o que sabe — em vez de exigir
        # que a S0 seja reescrita por causa do formato do relatório.
        report = Report.new(catalog: entry[:label], unchanged: resultado.respond_to?(:count) ? resultado.count : 0)
        io&.puts("   #{report}")
        report
      end

      # Os semeadores da S0 têm assinaturas diferentes entre si (`UserTypes`
      # aceita `io:`, `Permissions` não). O carregador se adapta em vez de
      # obrigar a S0 a mudar por causa dele — Princípio 6b.
      def invoke(seeder, io)
        seeder.method(:call!).parameters.any? { |tipo, nome| nome == :io && %i[key keyreq].include?(tipo) } ?
          seeder.call!(io: io) : seeder.call!
      end

      def missing_models(entry)
        Array(entry[:requires]).reject { |nome| GlobalCatalog.dependent_class(nome) }
      end
    end
  end
end

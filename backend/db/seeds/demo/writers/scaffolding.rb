# frozen_string_literal: true

module Demo
  module Writers
    # Prepara o terreno: garante os seeds de **referência** e retira os rastros de
    # conferência que a S0 deixou.
    #
    # Os projetos `alpha`/`beta` e os usuários `s0.*@sfg.test` foram criados para
    # conferir o contrato C1 e cumpriram o papel. Deixá-los faz a lista de clientes
    # da demonstração abrir com "Projeto Alpha" logo acima de "Grupo Aliança
    # Metalúrgica" — e o cliente lê os dois. A **DEC-64** previu esta limpeza.
    #
    # Os OGs da base ai9 (`vinaoxd@gmail.com` e companhia) **não** são tocados:
    # são as contas de quem desenvolve, não dado de demonstração.
    class Scaffolding < Base
      def self.requires = %w[User UserType Project]

      # Projetos que sobraram de VERIFICACAO de fatia e nao sao do elenco.
      #
      # `alpha`/`beta` vieram da conferencia da S0. `verificacao-s4-alfa` apareceu
      # em `sfg9_dev` as 02:46 de 26/08, criado a mao durante a verificacao da S4 —
      # nao ha uma linha sequer no repositorio que o crie.
      #
      # Ele importa porque **a lista de clientes da apresentacao abria com um
      # projeto vazio**: sem empresa, sem limite, sem nada. Quem apresenta nao tem
      # como saber que aquilo e sobra de teste.
      LEFTOVER_PROJECT_SLUGS = %w[alpha beta verificacao-s4-alfa].freeze
      LEFTOVER_USER_EMAILS = %w[
        s0.admin@sfg.test s0.gerente@sfg.test s0.colab@sfg.test s0.outro@sfg.test
      ].freeze

      def call
        ensure_reference_seeds!
        drop_leftovers!
      end

      private

      # Dado de REFERÊNCIA é pré-requisito, não demonstração — papéis (DEC-41),
      # permissões (DEC-18.6), tipos de garantia (DEC-86), contratos (OPS-330) e
      # os tipos de limite e de movimentação de risco (OPS-230/231).
      #
      # **Chama o carregador único da S3** (`Seeds::Reference::Runner`), e não
      # cada semeador na mão. Enquanto este módulo mantinha a própria lista, o
      # seed de demonstração aplicava dois dos seis catálogos e os quatro
      # restantes ficavam para quem lembrasse de rodar `rake reference:seed` —
      # e um `demo:seed` em banco recém-criado morria em `RiskOperationType`
      # ausente, que é justamente o que este método existe para evitar.
      #
      # O Runner é idempotente e **pula sozinho** o catálogo cuja fatia dona
      # ainda não entregou o model: o mesmo contrato dos escritores daqui.
      def ensure_reference_seeds!
        return unless defined?(::Seeds::Reference::Runner)

        io.puts '   ↳ aplicando os seeds de REFERÊNCIA (idempotentes)'
        ::Seeds::Reference::Runner.call!(io: io)
      end

      def drop_leftovers!
        projects = ::Project.where(slug: LEFTOVER_PROJECT_SLUGS)
        if projects.exists?
          io.puts "   ↳ removendo #{projects.count} projeto(s) de conferência da S0: " \
                  "#{projects.pluck(:slug).join(', ')}"
          # `users.current_project_id` tem FK com `on_delete: :nullify`, e
          # `memberships` cai por `dependent: :destroy`. `destroy_all` para que a
          # trilha do paper_trail registre a remoção.
          projects.destroy_all
        end

        users = ::User.where(email: LEFTOVER_USER_EMAILS)
        return unless users.exists?

        io.puts "   ↳ removendo #{users.count} usuário(s) de conferência da S0"
        users.destroy_all
      end
    end
  end
end

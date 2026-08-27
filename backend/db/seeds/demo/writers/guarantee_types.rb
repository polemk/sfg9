# frozen_string_literal: true

module Demo
  module Writers
    # Tipos de garantia — **DEC-86**.
    #
    # Este escritor **não tem lista própria**: ele delega para
    # `Seeds::Reference::GuaranteeTypes`, o seed de REFERÊNCIA (S3 / OPS-540).
    #
    # Por que delegar em vez de gravar aqui. Os tipos de garantia não são dado de
    # vitrine: **sem eles a tela de garantias do projeto sobe com o select
    # vazio** — que é literalmente o defeito do legado (a tabela existe desde
    # 2022 e nenhum seed a popula). Isso os torna dado de referência, e dado de
    # referência roda em todo deploy, não só quando alguém quer a demonstração.
    #
    # Enquanto as duas listas coexistiram, o resultado foi o previsível: quem
    # rodasse `demo:seed` antes de `reference:seed` criava as oito linhas **sem
    # a marca de provisório** (a coluna é `create_only` no seed de referência,
    # justamente para não desfazer a arrumação do usuário), e o selo nunca
    # aparecia na tela. Uma lista só resolve isso por construção.
    #
    # `Ledger::Ancillary::GUARANTEE_TYPES` continua existindo porque o RAZÃO
    # precisa dos títulos para montar as garantias dos controles **sem tocar no
    # banco** — e o spec `project_guarantee_types_spec.rb` reprova se as duas
    # listas divergirem.
    class GuaranteeTypes < Base
      def self.requires = %w[ProjectGuaranteeType]
      def self.owner_slice = 'S3'

      def call
        io.puts '   ⚠ tipos de garantia são PROVISÓRIOS (DEC-86) — a lista definitiva é do cliente'

        relatorio = ::Seeds::Reference::GuaranteeTypes.call!
        @created += relatorio.created
        @updated += relatorio.updated
        @unchanged += relatorio.unchanged
      end
    end
  end
end

# frozen_string_literal: true

module Seeds
  module Reference
    # S6 / **BE-160** — a alíquota de IOF vigente. REFERÊNCIA.
    #
    # Uma linha, com **vigência aberta** desde antes do primeiro borderô. Os dois
    # valores são os que estão cravados na fórmula do legado
    # (`../sfg/app/models/receivable_entry.rb:54`) e nunca mudaram em três anos
    # de produção — foi o que a conferência das 28.131 linhas mostrou: o
    # `checagem_iof` de todas elas fecha com estas duas alíquotas.
    #
    # Semear é o que fecha o **D-15**: com a linha, um recálculo histórico usa a
    # alíquota **da data do borderô**; sem ela, o calculador cai no valor de
    # origem — que hoje dá no mesmo, e no dia em que a alíquota mudar não daria.
    #
    # `valid_from` é **01/01/2016** e não 2022 de propósito: os borderôs mais
    # antigos vieram do sistema Django anterior, e o `legacy_id` de 17.610 linhas
    # de produção prova que eles existem. Uma vigência que começasse em 2022
    # deixaria essas linhas sem alíquota no recálculo.
    class IofRates < Catalog
      class << self
        def catalog_name = 'Alíquota de IOF (BE-160)'
        def model = ::IofRate
        def natural_key = %i[valid_from]
        # A alíquota de uma vigência JÁ ABERTA não se reescreve por deploy: ela
        # é o que calculou os borderôs daquele período.
        def create_only_attributes = %i[daily_rate fixed_rate note valid_to]

        def entries
          [{
            valid_from: Date.new(2016, 1, 1),
            valid_to: nil,
            daily_rate: BigDecimal('0.000041'),
            fixed_rate: BigDecimal('0.0038'),
            note: 'Alíquotas de origem, cravadas em `receivable_entry.rb:54`. ' \
                  'Conferidas contra as 28.131 linhas de produção: nunca mudaram.'
          }]
        end
      end
    end
  end
end

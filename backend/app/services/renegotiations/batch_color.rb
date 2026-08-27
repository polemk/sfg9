# frozen_string_literal: true

module Renegotiations
  # S9 / OPS-196 — **cor do lote de parcelas, com TERMINAÇÃO GARANTIDA**.
  #
  # A tela pinta cada lote de criação com uma cor, para que o usuário veja quais
  # parcelas entraram juntas. No legado (`renegotiation_installment.rb:104-114`):
  #
  #     loop do
  #       color = "##{ColorGenerator.new(saturation: 0.7, lightness: 0.3).create_hex}"
  #       break color unless RenegotiationInstallment.where(color:, renegotiation_id:).first
  #     end
  #
  # É um laço de rejeição **sem limite**: sorteia cor até achar uma que ainda não
  # foi usada nesta renegociação. Enquanto sobram cores ele termina rápido; quando
  # o espaço de cores usado se aproxima do total, o tempo esperado explode, e no
  # limite **ele não termina** — com uma consulta ao banco por tentativa.
  #
  # Aqui a paleta é **finita, fixa e determinística**:
  #
  #  - 12 cores escolhidas para ficarem legíveis nos dois modos (são usadas como
  #    faixa/ponto, não como fundo de texto);
  #  - a próxima cor é a primeira ainda não usada na renegociação;
  #  - **quando todas estão em uso, a paleta recomeça** — repetir cor é um
  #    incômodo visual, travar a criação de parcela é perda de função.
  #
  # Nada de `ColorGenerator` (gem a menos) e nada de cor aleatória: lote criado
  # duas vezes na mesma posição recebe a mesma cor, o que torna o teste possível.
  class BatchColor
    # Doze matizes espaçados de 30°, com saturação e luminosidade equivalentes às
    # do legado (`saturation: 0.7, lightness: 0.3`).
    PALETTE = %w[
      #4d1717 #4d3117 #4d4a17 #364d17 #1d4d17 #174d2b
      #174d45 #17384d #171f4d #2e174d #48174d #4d1739
    ].freeze

    def self.next_for(renegotiation_id)
      usadas = RenegotiationInstallment
               .where(renegotiation_id: renegotiation_id)
               .distinct
               .pluck(:color)
               .compact

      livre = PALETTE.find { |cor| usadas.exclude?(cor) }
      return livre if livre

      # Paleta esgotada: recomeça pela posição seguinte à última usada. Termina
      # sempre — que é o ponto desta classe.
      PALETTE[usadas.size % PALETTE.size]
    end
  end
end

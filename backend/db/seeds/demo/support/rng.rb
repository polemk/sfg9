# frozen_string_literal: true

require 'zlib'

module Demo
  module Support
    # Aleatoriedade **determinística e compartimentada** do seed de demonstração.
    #
    # Duas propriedades importam aqui, e as duas nasceram de problemas reais de
    # apresentação:
    #
    # 1. **Semente fixa** (`demo-seed-design.md` §10): rodar duas vezes dá o mesmo
    #    banco. Sem isso, "estava R$ 4,2 mi ontem" vira uma conversa ruim no meio da
    #    demo.
    # 2. **Um gerador por seção**, e não um global compartilhado. Com um gerador só,
    #    acrescentar uma garantia no fim do razão desloca todos os sorteios seguintes
    #    e **muda o borderô de dezembro**. Derivando a semente do nome da seção, cada
    #    parte da história é independente das outras.
    class Rng
      SEED = 20_260_828

      def initialize(seed = SEED)
        @seed = seed
        @streams = {}
      end

      # Gerador da seção. Sempre o mesmo para o mesmo nome.
      def for(section)
        @streams[section.to_sym] ||= Stream.new(Random.new(@seed + Zlib.crc32(section.to_s)))
      end

      # Gerador derivado de uma chave de negócio (ex.: o borderô de uma empresa num
      # mês). Permite gerar o registro N sem ter gerado os N-1 anteriores — o que
      # mantém o número estável quando a volumetria de outro cliente muda.
      def keyed(section, *parts)
        Stream.new(Random.new(@seed + Zlib.crc32("#{section}/#{parts.join('/')}")))
      end

      # Fachada com as amostragens que o razão usa. Nomes em inglês; a intenção,
      # nos comentários.
      class Stream
        def initialize(random)
          @random = random
        end

        def float(min, max)
          min + (@random.rand * (max - min))
        end

        def int(min, max)
          @random.rand(min..max)
        end

        def pick(list)
          list[@random.rand(list.length)]
        end

        # `shuffle(...).first(n)`, e **não** `Array#sample(n, random:)`: as duas
        # consomem o gerador de formas diferentes, e trocar uma pela outra muda
        # todos os números do seed a partir dali.
        #
        # Já aconteceu **duas vezes** por autocorreção de estilo. O `disable`
        # nomeava `Style/RedundantSort`, que não é o cop que corrige isto — quem
        # reescreve a linha é **`Style/Sample`**, e por isso `rubocop -a` passou
        # por cima da trava na segunda vez (26/08/2026). Os dois estão
        # desligados agora; se aparecer um terceiro, acrescente-o aqui em vez de
        # aceitar a correção.
        # rubocop:disable Style/RedundantSort, Style/Sample
        def sample(list, count)
          list.shuffle(random: @random).first(count)
        end
        # rubocop:enable Style/RedundantSort, Style/Sample

        def shuffle(list)
          list.shuffle(random: @random)
        end

        # `true` com probabilidade `probability`.
        def chance(probability)
          @random.rand < probability
        end

        # Escolha ponderada: `{ ended: 70, live: 25, overdue: 5 }`.
        def weighted(weights)
          total = weights.values.sum
          point = @random.rand * total
          weights.each do |key, weight|
            point -= weight
            return key if point <= 0
          end
          weights.keys.last
        end

        # Distribuição com **cauda** (log-uniforme): muitos valores perto do piso,
        # poucos perto do teto. É o que faz a lista de borderôs não parecer 12
        # empresas do mesmo tamanho (§3, princípio 4).
        def tailed(min, max)
          Math.exp(float(Math.log(min), Math.log(max)))
        end

        # Ruído multiplicativo em torno de 1,0 — usado para sazonalidade e para
        # tirar a regularidade dos totais mensais.
        def jitter(spread)
          1.0 + float(-spread, spread)
        end
      end
    end
  end
end

# frozen_string_literal: true

module Demo
  class Ledger
    # A série de **24 meses com história** — `demo-seed-design.md` §8.
    #
    # Dado uniforme dá gráfico reto, e gráfico reto não gera pergunta. A forma é o
    # que faz o cliente perguntar "o que aconteceu aqui?", que é exatamente a
    # pergunta que vende a ferramenta.
    #
    # Nenhuma data literal: tudo é `base_date - N.months`. Se a apresentação mudar
    # de dia, o seed não envelhece.
    module Timeline
      SPAN = 24

      # Sazonalidade por **mês do calendário**, não por índice da série. Dezembro e
      # janeiro caem de verdade no crédito a recebíveis; amarrar a queda ao índice
      # faria a retração cair em abril se o seed rodasse em outro mês.
      SEASONALITY = {
        1 => 0.76, 2 => 0.88, 3 => 1.06, 4 => 1.01, 5 => 1.03, 6 => 1.00,
        7 => 0.98, 8 => 1.02, 9 => 1.06, 10 => 1.09, 11 => 1.11, 12 => 0.70
      }.freeze

      # Degrau da entrada do FIDC Aurora (mês 9 da série = offset -15) e
      # crescimento de ~40% do mês 16 ao 24.
      AURORA_ENTRY = -15
      RECOVERY_START = -8

      module_function

      # `span` é a janela em meses. O padrão são os 24 do desenho; o spec do
      # orquestrador pede uma janela curta porque ele grava o seed inteiro
      # **uma vez por exemplo** — com os 24 meses são ~24 mil linhas por
      # exemplo, e a suíte inteira do repositório passaria a esperar por esta
      # fatia. Encurtar a série exercita os mesmos caminhos com um décimo das
      # gravações; quem confere volumetria é o spec do razão, que roda sem
      # banco.
      def months(base_date, rng, span: SPAN)
        stream = rng.for(:timeline)
        (-(span - 1)..0).map do |offset|
          date = base_date >> offset # `Date#>>` desloca meses
          trend = trend_for(offset)
          seasonality = SEASONALITY.fetch(date.month)
          Records::Month.new(
            offset: offset,
            date: Date.new(date.year, date.month, 1),
            year: date.year,
            month: date.month,
            label: format('%<m>02d/%<y>d', m: date.month, y: date.year),
            trend: trend,
            seasonality: seasonality,
            factor: trend * seasonality * stream.jitter(0.05)
          )
        end
      end

      # Meses 1–8 estáveis; degrau na entrada do Aurora; crescimento na
      # recuperação, terminando ~40% acima do início.
      def trend_for(offset)
        return 1.0 if offset < AURORA_ENTRY

        base = 1.08
        return base if offset < RECOVERY_START

        progress = (offset - RECOVERY_START).to_f / -RECOVERY_START
        base + (0.32 * progress)
      end

      # Modificador da história de cada cliente sobre o fator do mês.
      #
      # O cliente #11 é o único que **desce**: dificuldade a partir do mês 15
      # (offset -9), que é o que dá conteúdo à tela de renegociação e ao semáforo
      # de risco. Sem um cliente em dificuldade, o semáforo fica verde em 12 linhas
      # e a tela não prova nada.
      def client_modifier(client, month)
        case client.story
        when :dificuldade
          return 1.0 if month.offset < -9

          [1.0 - ((month.offset + 9) * 0.075), 0.28].max
        when :crescente
          1.0 + ((month.offset + 23) * 0.012)
        when :sazonal_forte
          # Insumo agrícola: concentra na safra e some fora dela.
          [3, 4, 8, 9, 10].include?(month.month) ? 1.55 : 0.62
        when :entrante
          1.0
        else
          1.0
        end
      end

      def active?(client, month)
        month.offset >= client.active_from
      end
    end
  end
end

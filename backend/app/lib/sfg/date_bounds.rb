# frozen_string_literal: true

module Sfg
  # Sentinelas de data do domínio — OPS-618.
  #
  # No legado isto era `config/initializers/date_overload.rb`, que reabria `DateTime`
  # para acrescentar `DateTime.dinosaurs` (agora − 2000 anos), `DateTime.mars`
  # (agora + 2000 anos), `today_start` e `today_end`. Os dois primeiros são o
  # "infinito" que o sistema escreve nos filtros de período quando o usuário não
  # informa data.
  #
  # Por que constante nomeada e não monkey patch: `Sfg::DateBounds::MIN` aparece no
  # diff e no grep; `DateTime.dinosaurs` não aparece em nenhum dos dois — e o nome não
  # diz que é sentinela, diz que é dinossauro. Quem lê um `where(date: DateTime.mars)`
  # não tem como saber que aquilo significa "sem limite superior".
  #
  # São **métodos**, não constantes congeladas no boot, porque o legado também os
  # calculava a cada chamada: um processo de longa duração que congelasse `TODAY_END`
  # no boot passaria a filtrar pelo dia errado depois da meia-noite.
  module DateBounds
    # Distância que o legado usa para representar "sem limite". Mantida em 2000 anos
    # para que qualquer comparação de paridade com dado migrado bata.
    SPAN = 2000

    module_function

    # Limite inferior aberto. Era `DateTime.dinosaurs`.
    def min
      Time.zone.now.midnight - SPAN.years
    end

    # Limite superior aberto. Era `DateTime.mars`.
    def max
      Time.zone.now.midnight + SPAN.years
    end

    # Era `DateTime.today_start`.
    def today_start
      Time.zone.now.midnight
    end

    # Era `DateTime.today_end`. O legado usa 23h59 — **não** 23h59m59s: um registro
    # gravado às 23:59:30 fica de fora do filtro "até hoje". Reproduzido de propósito;
    # corrigir muda quais linhas aparecem em relatório de fechamento.
    def today_end
      Time.zone.now.midnight + 23.hours + 59.minutes
    end

    # Intervalo que cobre tudo — o que o legado monta quando nenhuma ponta é informada.
    def unbounded
      min..max
    end
  end
end

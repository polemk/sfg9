# frozen_string_literal: true

# S10 / BE-322 (T-D11) — **tira o `update_all` de dentro do request**.
#
# Renomear um indicador reescreve `title`, `key` e `value_type` de **todas** as
# suas entries (`../sfg/app/models/indicator.rb:48-50`). O **resultado** é
# replicado — o histórico continua sendo reescrito, e há golden test travando
# isso (`G4`). O que muda é onde a escrita acontece: um indicador com 20.000
# lançamentos não pode travar o salvamento do formulário de edição.
#
# O corte está em `Indicator::PROPAGATION_INLINE_LIMIT`. Abaixo dele a
# propagação é síncrona (é uma linha de `UPDATE` e o usuário nem percebe);
# acima, vem para cá.
#
# `update_all` de propósito, aqui e no caminho síncrono: pula validações e
# callbacks e **não** toca `updated_at`, exatamente como o legado. Trocar por
# `find_each(&:save)` mudaria `updated_at` de milhares de linhas sem nenhum fato
# novo — e faria a trilha de auditoria acreditar que alguém editou cada uma.
class PropagateIndicatorFieldsJob < ApplicationJob
  queue_as :low_priority

  def perform(indicator_id)
    indicator = Indicator.find_by(id: indicator_id)
    # Indicador apagado entre o enfileiramento e a execução: não há o que
    # propagar, e isso não é erro.
    return Rails.logger.info("[PropagateIndicatorFieldsJob] indicador #{indicator_id} não existe mais") if indicator.nil?

    total = IndicatorEntry.propagate_from(indicator)
    Rails.logger.info(
      "[PropagateIndicatorFieldsJob] #{total} lançamento(s) do indicador #{indicator.id} " \
      "reescritos para title=#{indicator.title.inspect} key=#{indicator.key.inspect}"
    )
    total
  end
end

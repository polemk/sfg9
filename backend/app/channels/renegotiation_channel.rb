# frozen_string_literal: true

# S9 / FE-207 (backend), D-B5 — **os cartões de resumo atualizam por evento**.
#
# **Princípio 10: polling é proibido.** A tela de detalhe da renegociação mostra
# quatro cartões financeiros que mudam a cada parcela e a cada pagamento. Bater no
# servidor a cada N segundos para descobrir se mudou é o que este canal existe
# para não fazer — e é o que faz a mesma tela aberta em duas abas divergir.
#
# **Escopo (C1):** a assinatura só é aceita para quem participa do projeto da
# renegociação, e o nome do stream é derivado do id da renegociação. O
# `PermissionsChannel` da base aceita qualquer `user_id` que o cliente mandar (é a
# flag de upstream U2) — o padrão não se repete aqui, como já não se repetiu no
# `ProjectProgressChannel`.
#
# **O broadcast sai DEPOIS do COMMIT**, nunca de dentro da transação: emitido
# antes, o assinante recarrega e lê o estado anterior — um defeito que aparece
# como "o cartão atualizou com o número velho" e que ninguém associa a transação.
class RenegotiationChannel < ApplicationCable::Channel
  def subscribed
    renegotiation_id = params[:renegotiation_id]
    return reject if renegotiation_id.blank?
    return reject if current_user.blank?

    renegotiation = Renegotiation.find_by(id: renegotiation_id)
    return reject if renegotiation.blank?
    # A verdade é a linha de `memberships`, a mesma que `current_project!` usa.
    # OG e Admin enxergam todos os projetos (DEC-99).
    return reject unless authorized?(renegotiation)

    stream_from self.class.stream_name_for(renegotiation_id)
  end

  def self.stream_name_for(renegotiation_id)
    "renegotiation:#{renegotiation_id}"
  end

  # **Ponto único de emissão.** Serviços chamam isto — nunca
  # `ActionCable.server.broadcast` solto, senão o nome do stream vira convenção
  # oral e o primeiro erro de digitação some sem erro nenhum.
  def self.publish_changed(renegotiation)
    ActionCable.server.broadcast(
      stream_name_for(renegotiation.id),
      { event: 'renegotiation.changed', renegotiation_id: renegotiation.id, at: Time.current.iso8601 }
    )
  end

  private

  def authorized?(renegotiation)
    return true if current_user.og? || current_user.admin?

    current_user.member_of?(renegotiation.project_id)
  end
end

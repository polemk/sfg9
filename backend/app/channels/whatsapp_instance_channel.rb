# frozen_string_literal: true

# Transmite o estado da instância de WhatsApp em tempo real — QR novo, conexão
# aberta, conexão perdida.
#
# **Um stream só.** Antes, o canal assinava duas chaves (`instance_id` da
# Evolution **e** o `id` da linha) e o serviço transmitia para as duas: todo
# evento chegava **em dobro**. Era inofensivo enquanto a tela fosse idempotente,
# e deixaria de ser no primeiro `received` que contasse evento, animasse
# transição ou incrementasse algo.
#
# O nome do stream vive em `PolemkInstance.cable_stream_for` — derivá-lo em dois
# lugares foi o que permitiu os dois lados discordarem sem ninguém perceber.
class WhatsappInstanceChannel < ApplicationCable::Channel
  def subscribed
    # Defesa em profundidade. A conexao ja recusa anonimo desde que o
    # `ApplicationCable::Connection#connect` passou a chamar
    # `reject_unauthorized_connection` — mas este canal transmite o **QR de
    # pareamento**, que e credencial de acesso a conta de WhatsApp. Uma barreira
    # so, num canal desses, e uma barreira a menos do que se deve ter.
    return reject if current_user.blank?

    instance = PolemkInstance.find_for_cable(params[:instance_id])

    # Sem instância não há o que transmitir. Rejeitar é melhor que assinar um
    # stream que nunca recebe nada: o cliente sabe na hora, em vez de esperar
    # para sempre por um evento que não vem.
    if instance.nil?
      Rails.logger.info(
        "[WhatsappInstanceChannel] assinatura recusada — instância não encontrada para #{params[:instance_id].inspect}"
      )
      reject
      return
    end

    stream_from instance.cable_stream
    Rails.logger.info("[WhatsappInstanceChannel] assinado em #{instance.cable_stream}")
  end

  def unsubscribed
    # `connection.try` continua aqui de proposito: o `unsubscribed` roda tambem
    # numa assinatura RECUSADA, e nesse caminho `current_user` pode nao estar
    # preenchido — levantando `NameError` justamente no encerramento.
    #
    # (Ate 26/08 este `try` mascarava outra coisa: a conexao aceitava anonimo.
    # Isso foi corrigido em `ApplicationCable::Connection#connect`. O `try`
    # permanece pelo caso legitimo, nao mais pelo defeito.)
    Rails.logger.info("[WhatsappInstanceChannel] usuário #{connection.try(:current_user)&.id} desassinou")
  end

  # Ping do cliente para manter a conexão viva.
  def ping(data)
    Rails.logger.debug("[WhatsappInstanceChannel] ping: #{data}")
    transmit({ type: 'pong', timestamp: Time.current.iso8601 })
  end
end

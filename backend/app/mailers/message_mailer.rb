# frozen_string_literal: true

# S2 / BE-530 — e-mails da conversa, para quem enviou a mensagem.
#
# Mesmo motivo do `ObserverMailer`: o legado montava o HTML concatenando string
# em Ruby (`notification.rb:83-97`). Aqui é ERB.
class MessageMailer < ApplicationMailer
  # Confirmação de que a mensagem chegou.
  #
  # **BE-483 — o assunto é o do legado**, `"Obrigado, <primeiro nome> :)"`
  # (`feedback19/app/decorators/grind_mailer_decorator.rb:13`), e é também o que
  # o mapa da migração especifica (`map/data-infra.md:351`).
  #
  # Estava como "Recebemos sua mensagem — <app>": mais informativo, e divergente
  # sem registro nenhum. Pela **DEC-30** — onde a pergunta é replicar ou
  # corrigir, a resposta assinada é replicar — vale o texto do legado. O assunto
  # de um e-mail que o cliente recebe é interface, não detalhe interno: mudá-lo
  # é decisão do usuário, não do implementador.
  def received(message)
    @message = message
    @app_name = ENV.fetch('APP_NAME', 'Safegold')

    mail(to: message.sender_email, subject: "Obrigado, #{primeiro_nome(message.sender_name)} :)")
  end

  # Nova fala na thread. Vai para o **outro lado**: se quem escreveu foi o
  # administrador, avisa o remetente; se foi o remetente, o aviso é dos
  # observadores (`ObserverMailer`), e este e-mail não sai.
  def note_added(note)
    @note = note
    @message = note.admin_message
    @app_name = ENV.fetch('APP_NAME', 'Safegold')

    return unless note.from_admin?

    mail(to: @message.sender_email, subject: "Respondemos sua mensagem ##{@message.id} — #{@app_name}")
  end

  private

  # `name.split(" ")[0]` do legado, com guarda: conta sem nome deixaria o
  # assunto como "Obrigado,  :)".
  def primeiro_nome(nome)
    nome.to_s.split(' ').first.presence || 'e volte sempre'
  end
end

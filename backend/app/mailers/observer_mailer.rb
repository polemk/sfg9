# frozen_string_literal: true

# S2 / BE-530, OPS-394 — e-mails do observador.
#
# **A mudança que importa é o template.** No legado o HTML era montado por
# **concatenação de string dentro do Ruby** (`feedback19/lib/.../notification.rb:44-64`:
# `message << "<div style='…'>…"`, 20 linhas), marcado `html_safe` e entregue a
# um "generic message". Consequências: sem escape do que o usuário digitou, sem
# como revisar o e-mail sem ler Ruby, e nenhuma chance de alguém de design
# mexer. Aqui é ERB, com o layout `mailer` da casa e escape por padrão.
class ObserverMailer < ApplicationMailer
  # Chegou mensagem num contexto que este observador acompanha.
  def message_received(observer, message)
    @observer = observer
    @message = message
    @app_name = ENV.fetch('APP_NAME', 'Safegold')

    mail(to: observer.email, subject: "Nova mensagem no #{@app_name}")
  end

  # Alguém cadastrou este e-mail como observador.
  def added(observer)
    @observer = observer
    @admin = observer.user
    @app_name = ENV.fetch('APP_NAME', 'Safegold')

    mail(to: observer.email, subject: "#{primeiro_nome(@admin)} te incluiu no #{@app_name}")
  end

  # O cadastro foi removido.
  def removed(observer)
    @observer = observer
    @admin = observer.last_updated_user || observer.user
    @app_name = ENV.fetch('APP_NAME', 'Safegold')

    mail(to: observer.email, subject: "#{primeiro_nome(@admin)} te removeu no #{@app_name}")
  end

  private

  def primeiro_nome(user)
    user&.name.to_s.split(' ').first.presence || 'Um administrador'
  end
end

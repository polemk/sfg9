# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch('MAILER_FROM', 'no-reply@safegold.com.br')
  layout 'mailer'

  # S13 / DB-481 — falha de entrega vira LINHA, não ausência de linha.
  #
  # O `EmailDeliveryLogger` abaixo é um observador, e observador só roda quando a
  # entrega dá certo. Sem este `delivery_job`, um erro de SMTP deixava o log
  # exatamente igual a "ninguém tentou mandar" — e a pergunta que o log existe para
  # responder ("a pessoa recebeu o código de acesso?") ficava sem resposta.
  self.delivery_job = LoggedMailDeliveryJob

  # Identifica quem enviou, para o `EmailLog` (DEC-90). Vai em cabeçalho porque o
  # observador de entrega recebe a `Mail::Message` pronta, sem referência ao mailer que
  # a produziu — sem isto o log registraria remetente e assunto sem saber de qual
  # fluxo veio, que é justamente o que se quer saber numa investigação.
  before_action do
    headers['X-Mailer-Class'] = self.class.name
    headers['X-Mailer-Action'] = action_name
  end

  # O observador é registrado AQUI, e não num initializer de `config/`, porque
  # `config/` é território de outra fatia (S18) e porque este é o lugar onde a
  # dependência é óbvia: quem lê o mailer vê que todo envio é registrado.
  #
  # O guarda contra registro duplicado é necessário: em desenvolvimento o autoload
  # recarrega esta classe a cada mudança de arquivo, e sem ele o mesmo e-mail geraria
  # duas, três, dez linhas em `email_logs`.
  # `Mail` guarda os observadores numa variável de classe própria; é ela que responde
  # se este já está registrado.
  unless Mail.class_variable_get(:@@delivery_notification_observers).include?(EmailDeliveryLogger)
    ActionMailer::Base.register_observer(EmailDeliveryLogger)
  end

  # S13 / OPS-485, OPS-608 — **assinatura DKIM**, pelo mesmo caminho e pelo mesmo
  # motivo: mailer novo não precisa lembrar de assinar.
  #
  # O legado registrava isto em `config/application.rb` e lia a chave privada com
  # `open(Rails.root.join("lib","dkim_private_key.pem"))` **no boot** — arquivo
  # ausente derrubava a aplicação inteira. Aqui o registro não lê chave nenhuma:
  # quem resolve domínio, seletor e chave é o `Sfg::DkimSigner`, **na hora do
  # envio**. Sem chave o e-mail sai sem assinatura, com aviso; o boot não é
  # afetado nem quando `DKIM_DOMAIN` está configurado.
  #
  # Mesmo guarda contra registro duplicado do observador acima, pelo mesmo motivo
  # (autoload em desenvolvimento recarrega esta classe).
  unless Mail.class_variable_get(:@@delivery_interceptors).include?(Sfg::DkimInterceptor)
    ActionMailer::Base.register_interceptor(Sfg::DkimInterceptor)
  end
end

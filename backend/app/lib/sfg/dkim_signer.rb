# frozen_string_literal: true

module Sfg
  # S13 / OPS-485, OPS-608 — **assinatura DKIM como interceptor de mailer**.
  #
  # ## O que o legado fazia, e por que não dá para copiar
  #
  # `../sfg/config/application.rb:110-114`:
  #
  #     Dkim::domain      = 'safegold.com.br'
  #     Dkim::selector    = 'dk'
  #     Dkim::private_key = open(Rails.root.join("lib","dkim_private_key.pem")).read
  #     ActionMailer::Base.register_interceptor(Dkim::Interceptor)
  #
  # Três problemas, nesta ordem de gravidade:
  #
  # 1. **A chave privada estava no repositório**, em `lib/dkim_private_key.pem`.
  #    Chave de assinatura versionada é chave comprometida — quem clona o repo
  #    pode assinar e-mail como o domínio.
  # 2. **`open(...)` no boot.** Arquivo ausente = `Errno::ENOENT` **dentro do
  #    `config/application.rb`**, ou seja, a aplicação inteira não sobe. Um
  #    detalhe de e-mail derrubava o sistema, e derrubava em desenvolvimento
  #    todo dia (o `.pem` de produção não fica na máquina de quem desenvolve).
  # 3. **Domínio e seletor assados no código.** Trocar de domínio exige deploy.
  #
  # ## O que este arquivo faz
  #
  # - **domínio e seletor por ENV** (`DKIM_DOMAIN`, `DKIM_SELECTOR`);
  # - **chave privada como segredo**, resolvida **na hora do envio**, não no
  #   boot: primeiro `DKIM_PRIVATE_KEY`, depois o `Credential` de provedor
  #   `dkim` (DEC-61), que é encriptado por Active Record Encryption e trocável
  #   por tela **sem deploy**;
  # - **ausência de chave = envio DEGRADADO, nunca boot travado.** O e-mail sai
  #   sem assinatura e o aviso é registrado uma vez por processo (não a cada
  #   mensagem: um alerta repetido mil vezes deixa de ser lido);
  # - **falha de assinatura também degrada.** Interceptor que levanta **impede a
  #   entrega**. Entre "o e-mail de código de acesso não chega" e "o e-mail chega
  #   sem assinatura", a escolha é óbvia — e o erro fica no log com classe e
  #   mensagem, mais o estado consultável em `.status`.
  #
  # ## Como ligar em produção
  #
  #     DKIM_DOMAIN=safegold.com.br
  #     DKIM_SELECTOR=dk
  #     # e a chave, por UM dos dois caminhos:
  #     DKIM_PRIVATE_KEY="$(cat dkim_private_key.pem)"
  #     # …ou pela tela de credenciais, provedor `dkim`.
  #
  # Sem `DKIM_DOMAIN` o interceptor não faz nada e nada é registrado: é o estado
  # normal de desenvolvimento e de teste, não uma degradação.
  class DkimSigner
    CREDENTIAL_PROVIDER = 'dkim'
    DEFAULT_SELECTOR = 'dk'

    class << self
      def domain = ENV['DKIM_DOMAIN'].presence

      def selector = ENV.fetch('DKIM_SELECTOR', DEFAULT_SELECTOR).presence

      # Ligado = alguém declarou o domínio. É o único interruptor: sem domínio
      # não há o que assinar, e um `DKIM_ENABLED` separado só criaria um segundo
      # lugar para a configuração discordar de si mesma.
      def enabled? = domain.present?

      # Resolvida a cada envio, de propósito — a chave pode ser cadastrada com a
      # aplicação já no ar. `Credential` pode não estar disponível (banco fora,
      # migration pendente, `assets:precompile`): isso não é motivo para falhar.
      def private_key
        ENV['DKIM_PRIVATE_KEY'].presence || credential_key
      end

      # Estado consultável, para runbook e para o spec. Três valores:
      # `:disabled` (nem tenta), `:degraded` (quer assinar e não tem chave),
      # `:active`.
      def status
        return :disabled unless enabled?
        return :degraded if private_key.blank?

        :active
      end

      def degraded? = status == :degraded

      # Assina a mensagem no lugar. Devolve `true` se assinou.
      def sign!(message)
        return false unless enabled?

        chave = private_key
        if chave.blank?
          avisar_uma_vez('sem chave privada: DKIM_PRIVATE_KEY vazio e nenhum Credential de provedor ' \
                         "`#{CREDENTIAL_PROVIDER}`. O e-mail sai SEM assinatura.")
          return false
        end

        aplicar!(message, chave)
        true
      rescue StandardError => e
        # Nunca relança: exceção aqui **cancela a entrega**. O contrato D-C vale
        # para job; um interceptor de mailer é o caso oposto — ele é acessório
        # ao envio e não pode derrubá-lo. O erro fica nomeado no log.
        Rails.logger.error("[Sfg::DkimSigner] falha ao assinar (#{e.class}: #{e.message}). " \
                           'O e-mail segue SEM assinatura.')
        false
      end

      # Zera o aviso "uma vez por processo". Existe para o spec — em produção o
      # estado de degradação não muda dentro de um mesmo processo sem que
      # alguém cadastre a chave, e aí o próximo envio já assina.
      def reset_warning! = @avisado = nil

      private

      def credential_key
        Credential.by_provider(CREDENTIAL_PROVIDER).order(created_at: :desc).first&.api_key.presence
      rescue StandardError => e
        Rails.logger.warn("[Sfg::DkimSigner] não foi possível ler o Credential: #{e.class}: #{e.message}")
        nil
      end

      # A gem guarda opções em variáveis de módulo GLOBAIS (`Dkim::domain=`).
      # Aqui elas são passadas por instância — configuração global mutável num
      # processo com N threads de Sidekiq é corrida esperando para acontecer.
      def aplicar!(message, chave)
        require 'dkim'
        require 'mail/dkim_field'

        # Assinatura anterior é substituída, não somada: duas assinaturas na
        # mesma mensagem é o que o `Dkim::Interceptor` original avisa em `warn`.
        message['DKIM-Signature'] = nil if message['DKIM-Signature']

        assinatura = ::Dkim::SignedMail.new(message.encoded)
        assinatura.domain = domain
        assinatura.selector = selector
        assinatura.private_key = chave

        message.header.fields.unshift(Mail::DkimField.new(assinatura.dkim_header.value))
      end

      def avisar_uma_vez(mensagem)
        return if @avisado

        @avisado = true
        Rails.logger.warn("[Sfg::DkimSigner] ENVIO DEGRADADO — #{mensagem}")
      end
    end
  end
end

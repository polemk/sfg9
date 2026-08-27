# frozen_string_literal: true

module Sfg
  # S13 / OPS-485, OPS-608 — o interceptor registrado no `ApplicationMailer`.
  #
  # Fica separado do `Sfg::DkimSigner` porque `register_interceptor` guarda a
  # **classe**, e uma classe de um método só, com nome óbvio, é o que a pessoa
  # investigando um cabeçalho `DKIM-Signature` vai procurar no `grep`.
  #
  # **Ele nunca levanta.** Toda a política de degradação está no signer: sem
  # domínio configurado não faz nada; com domínio e sem chave, avisa uma vez e
  # deixa o e-mail sair sem assinatura. Interceptor que levanta **cancela a
  # entrega**, e o e-mail que este produto manda é o código de acesso — a
  # credencial (DEC-14).
  #
  # ## Por que a garantia precisa estar AQUI também, e não só no signer
  #
  # Ela era só declarada. Toda a proteção morava no `rescue` de `DkimSigner.sign!`
  # — o que deixa de fora exatamente o que acontece **antes** de a chamada entrar
  # no signer. Foi o que se viu em 26/08/2026:
  #
  #     NameError: uninitialized constant Sfg::DkimInterceptor::DkimSigner
  #     dkim_interceptor.rb:17:in 'Sfg::DkimInterceptor.delivering_email'
  #
  # e o job de envio do **código de acesso** morreu na fila. A causa foi de
  # bancada (worker `sidekiq` de horas, `config.eager_load = false` no
  # desenvolvimento e 5 threads resolvendo a constante ao mesmo tempo — em
  # produção o `eager_load = true` carrega tudo antes), mas a lição não é: uma
  # garantia que depende de a linha seguinte ser alcançada não é garantia.
  #
  # `NameError` é `StandardError`, então este `rescue` cobre o caso real
  # observado, além de qualquer outro tropeço na borda. O e-mail sai **sem
  # assinatura** — que é o mesmo desfecho já escolhido para "sem chave" — em vez
  # de não sair.
  class DkimInterceptor
    def self.delivering_email(message)
      DkimSigner.sign!(message)
      message
    rescue StandardError => e
      Rails.logger.error(
        "[Sfg::DkimInterceptor] falha ANTES da assinatura (#{e.class}: #{e.message}). " \
        'O e-mail segue SEM assinatura — cancelá-lo seria pior: ele carrega a credencial.'
      )
      message
    end
  end
end

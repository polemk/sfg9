# frozen_string_literal: true

module Contracts
  # S12 / BE-332, BE-341, BE-342 — **o que ainda falta este usuário aceitar**.
  #
  # Três defeitos do legado morrem aqui:
  #
  #  1. **A associação quebrada.** `has_many :contracts, through: :contract_deals,
  #     source: :contract_deal` (`user_decorator.rb:40`) aponta para uma `source`
  #     que não existe — `ContractDeal` declara `:contract` e `:user`. Qualquer
  #     usuário logado que abrisse `/contract/:type` recebia **500** (D-64).
  #  2. **Pendência calculada pelo que o usuário já aceitou**, e não pelo
  #     catálogo (BE-341). A consequência não é óbvia: quem **nunca** aceitou um
  #     tipo — porque o contrato foi criado depois da conta — **nunca ficava
  #     pendente dele**. O aceite pendente só existia para quem já tinha aceite.
  #  3. **A tolerância inerte.** O prazo existia e ninguém o consumia, porque o
  #     bloqueio que o consumia estava comentado (`pub_application_controller.rb:55-63`).
  #
  # **DEC-65: pendência é SINAL, não bloqueio.** Este serviço não barra nada — o
  # produto mostra banner e botão. Numa demo comercial, bloquear o acesso na
  # primeira tela trava o cliente. O ciclo completo com bloqueio está registrado
  # para o cutover, com o prazo que o jurídico definir.
  #
  # **DEC-66: `implicit_legacy` não conta.** Aceite carimbado pela base antiga
  # preserva o histórico e **não** satisfaz a pendência — o novo aceite explícito
  # é exigido na próxima entrada.
  module PendingService
    # Q-B5 / BE-342 — tolerância de 30 dias corridos da publicação. Continua
    # **inerte para acesso** (DEC-65 não bloqueia); o que ela decide é a
    # **urgência** que a interface comunica.
    TOLERANCE_DAYS = 30

    module_function

    # Uma entrada por tipo do catálogo que tem versão publicada e cujo aceite
    # explícito da versão vigente falta.
    #
    # Sem N+1: uma consulta para as vigentes, uma para os aceites do usuário.
    def call(user)
      vigentes = Resolver.current_all
      return [] if vigentes.empty?

      aceitos = if user.nil?
                  {}
                else
                  ContractDeal.for_user(user).explicit
                              .where(contract_id: vigentes.map(&:id))
                              .index_by(&:contract_id)
                end

      vigentes.reject { |c| aceitos.key?(c.id) }.map { |c| describe(c) }
    end

    def pending?(user)
      call(user).any?
    end

    # O histórico de aceites do usuário, do mais recente para o mais antigo.
    # Inclui os `implicit_legacy` — eles não satisfazem a pendência, mas são
    # justamente o que o usuário precisa ver para entender por que está sendo
    # pedido de novo (DEC-66).
    def history(user)
      ContractDeal.for_user(user).includes(:contract).order(accepted_at: :desc)
    end

    def describe(contract)
      prazo = contract.published_at + TOLERANCE_DAYS.days
      {
        id: contract.id,
        kind: contract.kind,
        slug: contract.slug_value,
        title: contract.title,
        version: contract.version,
        published_at: contract.published_at,
        # Informativo. Passado o prazo, a interface insiste mais; **o acesso
        # continua livre** (DEC-65).
        tolerance_until: prazo,
        overdue: Time.current > prazo
      }
    end
  end
end

# frozen_string_literal: true

module Contracts
  # S12 / BE-333, BE-347, DB-331 — **gravar o aceite, com prova** (DEC-80).
  #
  # O legado (`pub/contracts_controller.rb:15-25`) fazia
  # `ContractDeal.create(contract_deal_params)` com `:user_id` **no `permit`** e
  # só DEPOIS sobrescrevia com o usuário da sessão — o primeiro `create` já podia
  # gravar aceite **em nome de outro** (D-68). E `deal_for(user)`
  # (`contract.rb:60-66`) não checava o retorno do `save`: falha de gravação
  # respondia sucesso.
  #
  # Aqui o usuário é **sempre** o da sessão (não existe parâmetro para isso), a
  # gravação é idempotente, e a falha propaga.
  module AcceptService
    Result = Struct.new(:status, :deal, :error, :message, :code, keyword_init: true)

    module_function

    # `contract` é a versão a aceitar. Só a **vigente** é aceitável: aceitar uma
    # versão antiga produziria uma prova que já nasce desatualizada, e a pendência
    # continuaria de pé — o usuário clicaria de novo sem entender por quê.
    def call(user:, contract:, ip_address: nil, user_agent: nil)
      return Result.new(status: 401, error: 'unauthorized', message: 'Não autenticado') if user.nil?
      return Result.new(status: 404, error: 'not_found', message: 'Contrato não encontrado.') if contract.nil?

      vigente = Resolver.current(contract.kind)
      if vigente.nil? || vigente.id != contract.id
        return Result.new(status: 422, error: 'not_current_version', code: 'CONTRACT_NOT_CURRENT',
                          message: 'Só a versão vigente do contrato pode ser aceita.')
      end

      existente = ContractDeal.for_user(user).find_by(contract_id: contract.id)
      # Idempotente: clicar duas vezes é a mesma coisa que clicar uma. E um
      # aceite `implicit_legacy` da MESMA versão é promovido a explícito — é
      # exatamente o que a DEC-66 pede que aconteça na próxima entrada.
      if existente
        return Result.new(status: 200, deal: existente) if existente.explicit?

        return promote(existente, ip_address: ip_address, user_agent: user_agent)
      end

      deal = ContractDeal.new(
        user: user,
        contract: contract,
        accepted_at: Time.current,
        source: ContractDeal::SOURCE_EXPLICIT,
        contract_kind: contract.kind,
        contract_version: contract.version,
        ip_address: ip_address,
        user_agent: user_agent.to_s.presence&.first(1000),
        content_hash: contract.content_hash,
        accepted_body: contract.description_html
      )

      begin
        deal.save!
      rescue ActiveRecord::RecordNotUnique
        # Corrida entre duas abas. O índice único ganhou; o resultado desejado
        # (existe um aceite) foi alcançado.
        return Result.new(status: 200, deal: ContractDeal.for_user(user).find_by(contract_id: contract.id))
      rescue ActiveRecord::RecordInvalid => e
        # BE-347: falha **propagada e registrada**. O legado engolia.
        Rails.logger.error("[contracts] falha ao gravar aceite user=#{user.id} contract=#{contract.id}: #{e.message}")
        return Result.new(status: 422, error: 'invalid', message: e.record.errors.full_messages.to_sentence)
      end

      Result.new(status: 201, deal: deal)
    end

    # Aceita de uma vez tudo o que está pendente. É o que o botão do banner
    # chama (`POST /api/v1/me/terms`) — e é a rota que `READONLY_EXEMPT_PATHS`
    # isenta, porque bloquear o aceite do readonly o tranca fora do sistema.
    def accept_all_pending(user:, ip_address: nil, user_agent: nil)
      pendentes = PendingService.call(user)
      resultados = pendentes.map do |p|
        call(user: user, contract: Contract.find_by(id: p[:id]),
             ip_address: ip_address, user_agent: user_agent)
      end
      falha = resultados.find { |r| r.status >= 400 }
      return falha if falha

      Result.new(status: 200, deal: nil)
    end

    # Promoção de `implicit_legacy` a `explicit` na MESMA versão. O índice único
    # `(user_id, contract_id)` da DEC-80 só admite uma linha por versão, então a
    # data original vai para `legacy_accepted_at` — a DEC-66 manda preservá-la
    # como histórico, e sobrescrevê-la seria apagar o passivo em vez de marcá-lo.
    def promote(deal, ip_address:, user_agent:)
      contrato = deal.contract
      deal.assign_attributes(
        source: ContractDeal::SOURCE_EXPLICIT,
        legacy_accepted_at: deal.legacy_accepted_at || deal.accepted_at,
        accepted_at: Time.current,
        ip_address: ip_address,
        user_agent: user_agent.to_s.presence&.first(1000),
        content_hash: contrato.content_hash,
        accepted_body: contrato.description_html
      )
      unless deal.save
        Rails.logger.error("[contracts] falha ao promover aceite #{deal.id}: #{deal.errors.full_messages}")
        return Result.new(status: 422, error: 'invalid', message: deal.errors.full_messages.to_sentence)
      end

      Result.new(status: 200, deal: deal)
    end
  end
end

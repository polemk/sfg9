# frozen_string_literal: true

module Api
  module V1
    # S12 / BE-332..BE-334, BE-341..BE-343, BE-347 — **ler e aceitar** contrato.
    #
    # A separação de recursos é a **DEC-38**: aqui vive o recurso `contracts`,
    # que a matriz dá como `R` para os quatro papéis; **publicar** é o recurso
    # novo `contract_versions` (CRUD para OG e Admin), noutro arquivo. No legado
    # não havia recurso nenhum: `contracts_controller.rb` tem 101 linhas e
    # **zero** `before_action`, `may?`, `admin?`, `og?` ou `authorize`, as rotas
    # não têm constraint (`routes.rb:30-31`) e o `create` só carimba o `creator`
    # e salva. **Qualquer autenticado publicava os Termos de Uso.**
    #
    # **DEC-65 — o aceite é AÇÃO, sem bloqueio de acesso.** Nenhum endpoint aqui
    # barra ninguém por pendência; `GET /pending` é o que alimenta o banner
    # persistente e o botão. Ligar o bloqueio numa demo comercial arrisca travar
    # o cliente na primeira tela; o ciclo com bloqueio está registrado para o
    # cutover, com o prazo do jurídico.
    class Contracts < Grape::API
      helpers Api::V1::ControllerHelpers

      helpers do
        def find_contract!
          contrato = ::Contract.find_by(id: params[:id])
          # C1/C-1: id inacessível responde **igual** a id inexistente. Contrato é
          # catálogo global, então aqui não há escopo de projeto — mas a regra de
          # não virar oráculo de existência vale do mesmo jeito.
          error!({ error: 'not_found', message: 'Contrato não encontrado.' }, 404) if contrato.nil?
          contrato
        end
      end

      namespace :contracts do
        before { authenticate_user! }

        desc 'Contratos vigentes, um por tipo' do
          summary 'Contratos vigentes'
          detail 'Uma linha por tipo, com a versão mais recente. O agrupamento vem ANTES da paginação.'
        end
        get '' do
          authorize!('contracts', :read)
          # BE-334: o agrupamento acontece no banco (`DISTINCT ON`), não em Ruby
          # depois do `limit`. Paginar antes de agrupar é o D-20 nesta
          # capability — fazia contrato sumir da lista.
          Api::Entities::Contract.represent(::Contracts::Resolver.current_all)
        end

        desc 'O que este usuário ainda não aceitou' do
          detail 'Alimenta o banner persistente (DEC-65). NÃO bloqueia acesso.'
        end
        get 'pending' do
          authorize!('contracts', :read)
          ::Contracts::PendingService.call(current_user)
        end

        desc 'Uma versão de contrato, com o texto'
        params do
          requires :id, type: String
        end
        get ':id' do
          authorize!('contracts', :read)
          Api::Entities::Contract.represent(find_contract!, type: :full)
        end

        desc 'Aceita a versão vigente do contrato' do
          detail 'Sempre em nome do usuário da sessão. Idempotente. Só a versão vigente. ' \
                 'Isento do gate de somente-leitura (READONLY_EXEMPT_PATHS).'
        end
        params do
          requires :id, type: String
        end
        # PUT, e não POST, porque o efeito é idempotente — e porque é o verbo
        # que o legado já usava (`routes.rb:47`), o que mantém qualquer
        # integração externa funcionando.
        #
        # ⚠️ O caminho `/api/v1/contracts/:id/accept` **tem** de casar
        # `ControllerHelpers::READONLY_EXEMPT_PATHS`. A S0 escreveu o padrão
        # antes de a rota existir; esta é a rota, e o spec
        # `contracts_readonly_spec` prova que casa.
        put ':id/accept' do
          # Sem `authorize!('contracts', :create)`: aceitar não é criar contrato,
          # é exercer um direito do próprio usuário sobre um catálogo global. A
          # matriz dá `R` a todos os papéis, e é `R` que basta — exigir mais
          # trancaria fora exatamente quem precisa aceitar.
          authorize!('contracts', :read)
          contrato = find_contract!

          resultado = ::Contracts::AcceptService.call(
            user: current_user, contract: contrato,
            ip_address: request.ip, user_agent: request.user_agent
          )
          if resultado.status >= 400
            error!({ error: resultado.error, message: resultado.message, code: resultado.code }.compact,
                   resultado.status)
          end

          status resultado.status
          Api::Entities::ContractDeal.represent(resultado.deal)
        end
      end

      # ---------------------------------------------------------------------
      # `/api/v1/me/terms` — o aceite em bloco, do próprio usuário.
      # ---------------------------------------------------------------------
      # É a segunda rota que `READONLY_EXEMPT_PATHS` isenta, e ela existe por um
      # motivo concreto: o banner da DEC-65 pede o aceite de **tudo o que está
      # pendente** num clique. Sem isto, um usuário com dois contratos pendentes
      # teria de aceitar duas vezes, e o banner ficaria de pé depois do primeiro
      # clique parecendo que não funcionou.
      namespace :me do
        before { authenticate_user! }

        namespace :terms do
          desc 'Situação dos Termos para o usuário da sessão' do
            detail 'Pendências + histórico de aceites, inclusive os `implicit_legacy` (DEC-66).'
          end
          get '' do
            authorize!('my_account', :read)
            {
              pending: ::Contracts::PendingService.call(current_user),
              accepted: Api::Entities::ContractDeal.represent(
                ::Contracts::PendingService.history(current_user)
              ).as_json
            }
          end

          desc 'Aceita de uma vez tudo o que está pendente'
          post '' do
            authorize!('my_account', :read)
            resultado = ::Contracts::AcceptService.accept_all_pending(
              user: current_user, ip_address: request.ip, user_agent: request.user_agent
            )
            if resultado.status >= 400
              error!({ error: resultado.error, message: resultado.message, code: resultado.code }.compact,
                     resultado.status)
            end

            status 200
            {
              pending: ::Contracts::PendingService.call(current_user),
              accepted: Api::Entities::ContractDeal.represent(
                ::Contracts::PendingService.history(current_user)
              ).as_json
            }
          end
        end
      end
    end
  end
end

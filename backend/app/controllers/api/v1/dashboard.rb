# frozen_string_literal: true

module Api
  module V1
    # S15 / **NEW-002** e **NEW-001 (parte 2)** — a leitura do painel.
    #
    # ## Feature NOVA. Não procure no legado
    #
    # O `dash` do legado é uma tela vazia (`dash/_body.js.erb:8-22`) e não há
    # nenhuma agregação de painel na origem (`DB-399`, `dropped`). Estes dois
    # endpoints existem por decisão do usuário (DEC-21), e no `parity-ledger.md`
    # entram como `new`.
    #
    # ## Compositor, nunca agregador
    #
    # **Não há um único `SUM` financeiro neste arquivo, e isso é o portão da
    # tarefa 2.1.** Todo número vem de um serviço de domínio que já o calcula
    # para a tela de detalhe correspondente (contrato **C2**). Escrever a soma
    # aqui daria ao sistema duas fórmulas para o mesmo valor — o **D-09**.
    #
    # ## Escopo (C1) e a lição do D-110
    #
    # Os dois endpoints chamam `current_project!`. Um agregado sem escopo é o
    # pior tipo de vazamento: o número atravessa o projeto **sem mostrar a
    # linha**, então ninguém percebe olhando a tela. Projeto inexistente e
    # projeto sem participação respondem o **mesmo** status, herdado do helper —
    # distinguir 403 de 404 transformaria o painel num oráculo de ids.
    #
    # ## Somente leitura entra
    #
    # Nada aqui grava, então `require_not_readonly!` (que só age em verbo de
    # escrita) não alcança estas rotas. `user_is_readonly` vê o painel inteiro.
    class Dashboard < Grape::API
      helpers Api::V1::ControllerHelpers

      # O recurso `dash` da matriz DEC-18: `R` para os quatro papéis. A permissão
      # **por cartão** é outra coisa, e mora no `SummaryService` — quem não pode
      # ver renegociação não recebe o cartão, em vez de recebê-lo zerado.
      RESOURCE = 'dash'

      namespace :dashboard do
        before { authenticate_user! }

        desc 'O resumo da tela inicial' do
          summary 'Resumo do projeto corrente'
          detail 'NEW-002 — quatro números e uma série, todos vindos dos serviços de domínio que já os ' \
                 'calculam (contrato C2). Cartão que o papel não pode ver **não vem no payload** — ele ' \
                 'some, não vem zerado. `value: null` = sem dado, distinguível de zero (D-117).'
        end
        params do
          optional :date, type: Date, desc: 'Data de apuração dos números pontuais. Padrão: hoje'
          optional :months, type: Integer, values: 1..36, desc: 'Meses da janela do total operado. Padrão: 12'
        end
        get 'summary' do
          authorize!(RESOURCE, :read)
          projeto = current_project!

          ::Dashboard::SummaryService.call(
            project: projeto,
            user: acting_user,
            date: params[:date] || Date.current,
            months: params[:months] || ::Dashboard::SummaryService::DEFAULT_MONTHS
          )
        end

        desc 'Volume por portador' do
          summary 'Exposição por portador numa data'
          detail 'NEW-001 (parte 2) — o limite utilizado de cada limite ativo, acumulado por portador, ' \
                 'vindo de `Risk::AggregateService` (BE-249/BE-251). Formato `{ labels, values }`, que é o ' \
                 'que `RechartsBar` já consome. Lista vazia = **não há limite ativo no projeto**, que não ' \
                 'é o mesmo que "todos zerados".'
        end
        params do
          optional :date, type: Date, desc: 'Data de apuração. Padrão: hoje'
        end
        get 'volume_by_carrier' do
          # O dado é de risco, então o gate é o de risco — e não o do painel.
          # Um endpoint de leitura que herda o gate errado é como um agregado
          # passa a mostrar o que a tela de origem esconde.
          authorize!('risk', :read)
          projeto = current_project!

          data = params[:date] || Date.current
          linhas = ::Risk::AggregateService.volume_by_carrier_on(projeto, data)

          {
            date: data.to_s,
            labels: linhas.map { |linha| linha[:label] },
            values: linhas.map { |linha| linha[:value] },
            has_data: linhas.any? { |linha| linha[:value].to_d.nonzero? }
          }
        end
      end
    end
  end
end

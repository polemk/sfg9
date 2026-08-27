# frozen_string_literal: true

module Api
  module V1
    # S11 / BE-117, BE-149 — **o painel de disponibilidade**: indicadores do mês,
    # datas com lançamento e os totais por padrão base.
    #
    # ## Este endpoint é o D-01, o pior caso da família C1
    #
    # No legado, `app/controllers/api/v1/project_availability_controller.rb`
    # herda de `ApplicationController` — **não** do `PubApplicationController` —
    # e a primeira linha do `before_action` é:
    #
    #     @project = Project.find(params[:id] || params[:project_id])
    #
    # Sem sessão e sem escopo. **Qualquer requisição, de qualquer origem, lia a
    # disponibilidade de qualquer projeto por id.** Não é "o filtro é descartado
    # quando chega um id", como nos irmãos D-16/D-29/D-76/D-100 — é **não havia
    # filtro nem autenticação**. É de onde a família inteira tira o nome, e não
    # se replica um IDOR (DEC-30, exceção 2).
    #
    # No ai9:
    #
    #  - montado em `api/v1/base.rb`, que roda `require_not_readonly!` e herda o
    #    gate de credencial do `Api::Root` — **sem sessão responde 401**;
    #  - o projeto vem de `current_project!`, revalidado contra `memberships` a
    #    cada request;
    #  - o `:id` da rota é **validado contra o projeto corrente**, nunca usado
    #    para buscar. Id de outro projeto responde **404**, igual a id
    #    inexistente — distinguir 403 de 404 transformaria o endpoint num
    #    oráculo de ids.
    #
    # ## Sem dupla serialização (BE-149)
    #
    # O legado fazia `@dates = JSON.generate(values)` e depois
    # `render json: @dates` — uma **string JSON dentro de um JSON**, que o
    # cliente tinha de desserializar duas vezes. Aqui o corpo é o objeto.
    # **O nome da classe é `AvailabilityPanel`, e não `Availability`, de
    # propósito.** Uma classe `Api::V1::Availability` **sombreia** o módulo de
    # serviços `::Availability` dentro de todo o escopo léxico `Api::V1::*`: os
    # outros três endpoints da fatia passaram a resolver
    # `Availability::ProjectTemplateService` como
    # `Api::V1::Availability::ProjectTemplateService` e respondiam **500**. O
    # `zeitwerk:check` passava e o `ruby -c` também — só a requisição de verdade
    # mostrou. A rota continua `/api/v1/availability`.
    class AvailabilityPanel < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'availability'

      helpers do
        # Os indicadores, para as duas rotas. Uma implementação só — duas seriam
        # duas semânticas de painel.
        def availability_panel_payload(project)
          resultado = ::Availability::GridService.panel(
            project: project, date: params[:date], month: params[:month],
            year: params[:year], company_id: params[:company_id]
          )
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200

          dados = resultado[:data]
          {
            project_id: project.id,
            # FE-126 (`reuse`) — a observação do projeto em modo leitura. Vem do
            # `has_rich_text :availability_note` que a S4 entregou.
            observation_html: project.availability_note.body.to_s.presence,
            company_id: dados[:company]&.id,
            # FE-122 — as datas que TÊM lançamento, para o calendário marcar.
            dates: dados[:dates].map(&:to_s),
            # FE-124 — a contagem de lançamentos com valor ≠ 0 nas folhas.
            count: dados[:count],
            # **DEC-27 — o rótulo é a decisão.** Cada card é `virtual_value`,
            # que é *saldo acumulado*, não soma bruta. O `values[:total]` do
            # legado (soma bruta de `value`) era calculado e **nunca
            # renderizado**; a DEC-27 o classificou como código morto a remover
            # nesta fatia, e ele não está aqui.
            by_entry_label: 'Saldo acumulado',
            by_entry: dados[:by_entry].map do |item|
              {
                id: item[:id], name: item[:name],
                # **FE-125 — o sinal vai no próprio número.** O legado enviava o
                # módulo (`total * -1` no JS) e sinalizava só por vermelho:
                # ambíguo e inacessível.
                total: item[:total].to_s,
                operation_type: item[:operation_type],
                position_path: item[:position_path]
              }
            end
          }
        end
      end

      namespace :availability do
        before { authenticate_user! }

        desc 'Indicadores do painel de disponibilidade do projeto corrente' do
          summary 'Painel de disponibilidade'
          detail 'BE-117 / BE-149 — autenticado e escopado por `current_project!`. Fecha o D-01.'
        end
        params do
          optional :date, type: String, desc: 'Data específica (AAAA-MM-DD)'
          optional :month, type: Integer, desc: 'Mês do intervalo. Inválido → 422 (o legado dava 500)'
          optional :year, type: Integer
          optional :company_id, type: String, desc: 'Em branco = consolidação geral'
        end
        get '' do
          authorize!(RESOURCE, :read)
          project = current_project!

          availability_panel_payload(project)
        end
      end

      # A rota de paridade com o legado. O `:id` **não busca nada** — ele é
      # conferido contra o projeto que `current_project!` já resolveu.
      namespace :projects do
        route_param :id, type: String do
          before { authenticate_user! }

          desc 'Indicadores do painel de disponibilidade de um projeto' do
            detail 'O `:id` é VALIDADO contra a participação, nunca usado para buscar. Projeto de que ' \
                   'o usuário não participa → 404, igual a id inexistente.'
          end
          params do
            optional :date, type: String
            optional :month, type: Integer
            optional :year, type: Integer
            optional :company_id, type: String
          end
          get 'availability' do
            authorize!(RESOURCE, :read)

            # `Project.visible_to` é **a mesma consulta** que `current_project!`
            # roda por dentro (`resolve_current_project`), e é ela — não o
            # `params[:id]` — que decide. Id malformado nem chega ao Postgres:
            # comparar `uuid` com texto qualquer levanta
            # `PG::InvalidTextRepresentation`, e 500 numa URL digitada errada é
            # ruído que esconde erro de verdade.
            project_not_found! unless params[:id].to_s.match?(ProjectScopedService::UUID_FORMAT)

            project = Project.visible_to(current_user).find_by(id: params[:id])
            project_not_found! if project.nil?

            availability_panel_payload(project)
          end
        end
      end
    end
  end
end

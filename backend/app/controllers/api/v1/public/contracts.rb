# frozen_string_literal: true

module Api
  module V1
    module Public
      # S12 / BE-330, BE-349 — **a superfície pública** dos contratos.
      #
      # Monta no `namespace :public` que já existia (`api/v1/base.rb`, hoje com
      # `Public::Media` e `Public::Chat`) e entra na allowlist de `Api::Root`
      # **por rota**, nunca por cabeçalho.
      #
      # ## D-69 — duas vulnerabilidades no mesmo parâmetro
      #
      # O `redirect_url` do legado (`pub/contracts_controller.rb:3`) era
      # interpolado na view e usado como destino: **XSS refletido** e **open
      # redirect** na mesma variável. Aqui o parâmetro não é uma URL — é uma
      # **chave** de `Contracts::ReturnDestinations`, e o servidor devolve o
      # caminho. Valor desconhecido cai no destino padrão. Não existe caminho em
      # que texto do visitante vire `href`.
      #
      # ## BE-349 — a rota sem tipo
      #
      # `GET /contract` sem `:type` fazia `Contract.where(...).last` devolver
      # `nil` e a linha seguinte chamava `.kind` nele: **500, sempre**. Aqui,
      # sem tipo, a resposta é a lista de tipos disponíveis.
      #
      # ## Q-B34 — a URL em português
      #
      # As URLs públicas do legado carregam o tipo em português, com espaço e com
      # o typo consolidado (`Politicas de Privacidade`), e **existem em links
      # externos**. A resolução: o **slug** (`termos-de-uso`) é a forma canônica
      # das URLs novas e a **string literal continua sendo aceita** — as duas
      # entram por `Contract.kind_for`. Nada quebra e nada novo nasce feio.
      class Contracts < Grape::API
        helpers Api::V1::ControllerHelpers

        namespace :contracts do
          desc 'Tipos de contrato disponíveis' do
            detail 'BE-349 — sem tipo, lista os disponíveis. Nunca 500.'
          end
          get '' do
            kinds = ::Contracts::Resolver.available_kinds
            error!({ error: 'not_found', message: 'Nenhum contrato publicado.' }, 404) if kinds.empty?

            {
              kinds: kinds.map do |k|
                { kind: k, slug: ::Contract::SLUGS.fetch(k, k.parameterize) }
              end,
              return_destinations: ::Contracts::ReturnDestinations.keys
            }
          end

          desc 'O contrato vigente de um tipo, para leitura sem sessão'
          params do
            requires :kind, type: String, desc: 'Tipo (slug ou string literal)'
            optional :return_to, type: String, desc: 'CHAVE de destino, nunca uma URL (D-69)'
          end
          get ':kind', requirements: { kind: %r{[^/]+} } do
            contrato = ::Contracts::Resolver.current(params[:kind])
            # Tipo desconhecido é 404, não 500 — e não é oráculo: a resposta é a
            # mesma para "tipo não existe" e "tipo existe e não tem versão".
            error!({ error: 'not_found', message: 'Contrato não encontrado.' }, 404) if contrato.nil?

            Api::Entities::Contract.represent(contrato, type: :full).as_json.merge(
              # O destino resolvido pelo SERVIDOR, a partir da allowlist. O
              # cliente recebe um caminho conhecido, nunca o que mandou.
              return_to: ::Contracts::ReturnDestinations.resolve(params[:return_to]),
              return_to_allowed: ::Contracts::ReturnDestinations.allowed?(params[:return_to])
            )
          end
        end
      end
    end
  end
end

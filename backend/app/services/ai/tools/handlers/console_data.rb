# frozen_string_literal: true

module Ai
  module Tools
    module Handlers
      # As ferramentas de DADO do assistente (capability `console_data`).
      #
      # ## Aqui não nasce número — a mesma regra do painel
      #
      # Não existe um `SUM` financeiro neste arquivo, e é proposital: todo valor
      # vem do serviço de domínio que já o calcula para a tela correspondente
      # (contrato **C2**). O `project_snapshot` é literalmente o payload do
      # `Dashboard::SummaryService`, o compositor do painel; o
      # `overdue_renegotiations` e o `volume_by_carrier` chamam os mesmos
      # agregadores que ele chama.
      #
      # Se o assistente somasse por conta própria, o sistema passaria a ter duas
      # fórmulas para "total operado" — o defeito **D-09** — e a divergência
      # apareceria no pior lugar possível: uma conversa, onde ninguém confere o
      # número contra a tela.
      #
      # ## O que o assistente NÃO alcança
      #
      # Conta, permissão, credencial, trilha de auditoria e as telas de
      # administração ficam fora para **todo papel**, inclusive OG — a lista está
      # em `ConsoleScope::FORBIDDEN_RESOURCES`. O que sobra é o dado operacional
      # do projeto corrente, com a matriz DEC-18 aplicada recurso a recurso: o
      # `SummaryService` já omite o cartão que o papel não alcança, em vez de
      # devolvê-lo zerado.
      #
      # ## Ausência não é zero (D-117), e sinal é dado (DEC-01)
      #
      # `value: null` chega ao modelo junto com `has_value: false`, e o prompt
      # manda dizer "não há lançamento no período" nesse caso — `R$ 0,00`
      # afirmaria que se operou zero. Os rótulos monetários saem de
      # `Risk::Money.brl`, o mesmo formatador do resto do produto, para que o
      # negativo apareça como está em vez de o modelo "arrumá-lo".
      module ConsoleData
        # Teto do que o agente lista de uma vez. O painel corta em 6 porque é um
        # cartão; a conversa pode ir além, mas não pode virar exportação.
        MAX_ROWS = 30

        module_function

        # O retrato do projeto corrente: os cartões, a série do total operado, os
        # limites por tipo, quem está perto do teto e as renegociações em atraso.
        def project_snapshot(args, scope)
          bloqueio = scope.block_for_data('dash')
          return bloqueio if bloqueio

          data  = parse_date(args['date'])
          meses = parse_months(args['months'])

          payload = ::Dashboard::SummaryService.call(
            project: scope.project, user: scope.user, date: data, months: meses
          )

          {
            success: true,
            message: {
              project: payload[:project][:name],
              date: payload[:date],
              period: payload[:period],
              cards: Array(payload[:cards]).map { |card| card_for_model(card) },
              series: payload[:series],
              limits: limits_for_model(payload[:limits]),
              near_ceiling: near_ceiling_for_model(payload[:near_ceiling]),
              overdue_renegotiations: overdue_for_model(payload[:overdue_renegotiations]),
              # O que veio `nil` veio por FALTA DE PERMISSÃO, não por falta de
              # dado — e o modelo precisa saber a diferença para dizer "seu
              # perfil não alcança" em vez de "não há nada".
              hidden_by_role: %i[series limits near_ceiling overdue_renegotiations]
                              .select { |chave| payload[chave].nil? }
            }.to_json
          }
        end

        # A lista completa de renegociações em atraso — o painel corta em 6, aqui
        # o corte é `MAX_ROWS` e o total vem junto para o agente poder dizer
        # quantas ficaram de fora. Truncar em silêncio mentiria sobre o tamanho
        # do problema.
        def overdue_renegotiations(args, scope)
          bloqueio = scope.block_for_data('renegotiations')
          return bloqueio if bloqueio

          data   = parse_date(args['date'])
          limite = args['limit'].blank? ? MAX_ROWS : [[args['limit'].to_i, 1].max, MAX_ROWS].min

          escopo = ::Renegotiation.for_project(scope.project)
          unless escopo.exists?
            return { success: true, message: { date: data.to_s, total: 0, items: [], has_data: false }.to_json }
          end

          todas = ::Renegotiations::AggregateService.overdue_renegotiations_on(escopo, today: data)

          {
            success: true,
            message: {
              date: data.to_s,
              total: todas.size,
              shown: [todas.size, limite].min,
              items: todas.first(limite).map do |linha|
                {
                  title: linha[:title],
                  provider: linha[:provider_name],
                  kind: linha[:kind],
                  overdue_count: linha[:overdue_count],
                  total_debt: ::Risk::Money.brl(linha[:total_debt])
                }
              end,
              has_data: todas.any?
            }.to_json
          }
        end

        # Exposição acumulada por portador na data — a pergunta de concentração.
        # Lista vazia quer dizer **não há limite ativo no projeto**, que não é o
        # mesmo que "todos os portadores estão zerados" (é a nota do endpoint
        # `dashboard/volume_by_carrier`, e vale igual aqui).
        def volume_by_carrier(args, scope)
          bloqueio = scope.block_for_data('risk')
          return bloqueio if bloqueio

          data   = parse_date(args['date'])
          linhas = ::Risk::AggregateService.volume_by_carrier_on(scope.project, data)

          {
            success: true,
            message: {
              date: data.to_s,
              items: linhas.first(MAX_ROWS).map { |l| { carrier: l[:label], used: ::Risk::Money.brl(l[:value]) } },
              has_data: linhas.any?
            }.to_json
          }
        end

        # --- Apoio ---------------------------------------------------------

        def card_for_model(card)
          valor = card[:value]
          {
            key: card[:key],
            label: card[:label],
            hint: card[:hint],
            # `has_value: false` é o D-117 atravessando a ferramenta inteira.
            has_value: !valor.nil?,
            value: formatted_card_value(card, valor),
            screen: card[:href]
          }
        end

        def formatted_card_value(card, valor)
          return nil if valor.nil?

          card[:format] == 'currency' ? ::Risk::Money.brl(valor) : valor.to_i
        end

        def limits_for_model(limits)
          return nil if limits.nil?

          {
            date: limits[:date],
            has_data: limits[:has_data],
            items: limits[:items].first(MAX_ROWS).map do |item|
              {
                label: item[:label],
                used: ::Risk::Money.brl(item[:used]),
                total: ::Risk::Money.brl(item[:total]),
                available: ::Risk::Money.brl(item[:available]),
                # Vem PRONTO do serviço (`Money.percent`) e é repassado como
                # chegou: é ele que carrega o comportamento que a DEC-01 preserva.
                percent: item[:percent_label],
                at_ceiling: item[:at_ceiling]
              }
            end
          }
        end

        def near_ceiling_for_model(near)
          return nil if near.nil?

          {
            date: near[:date],
            threshold_percent: near[:threshold],
            has_data: near[:has_data],
            items: near[:items].first(MAX_ROWS).map do |item|
              {
                title: item[:title],
                carrier: item[:carrier_title],
                operation_type: item[:operation_type_title],
                used: ::Risk::Money.brl(item[:used]),
                total: ::Risk::Money.brl(item[:total]),
                available: ::Risk::Money.brl(item[:available]),
                percent: ::Risk::Money.percent(item[:percent])
              }
            end
          }
        end

        def overdue_for_model(overdue)
          return nil if overdue.nil?

          {
            date: overdue[:date],
            total: overdue[:total],
            has_data: overdue[:has_data],
            items: overdue[:items].map do |item|
              {
                title: item[:title],
                provider: item[:provider_name],
                overdue_count: item[:overdue_count],
                total_debt: ::Risk::Money.brl(item[:total_debt])
              }
            end
          }
        end

        # Data inválida vinda do modelo não estoura nem vira 1970: vira hoje. O
        # agente recebe a data efetiva de volta no payload e pode corrigir a
        # frase se tiver entendido errado.
        def parse_date(value)
          return Date.current if value.blank?

          Date.parse(value.to_s)
        rescue ArgumentError, TypeError
          Date.current
        end

        def parse_months(value)
          return ::Dashboard::SummaryService::DEFAULT_MONTHS if value.blank?

          [[value.to_i, 1].max, 36].min
        end
      end
    end
  end
end

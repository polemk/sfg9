# frozen_string_literal: true

module Api
  module Entities
    # S7 / **FE-250, FE-264, FE-265** — **operação de risco**.
    #
    # Valores monetários saem como **número** (decimal serializado), não string
    # formatada: quem formata é a tela, com `formatMoney`/`formatPercent`, que
    # leem a moeda de `@/lib/config/currency` (§5.4.9). Nenhum componente React
    # recalcula saldo — contrato **C2**.
    #
    # ### `original_balance` sai NEGATIVO, e é de propósito (DEC-01)
    #
    # `FE-265`: a aba GERAL do detalhe mostra "Saldo Inicial" **com o sinal
    # negativo gravado**, enquanto o formulário de edição mostra o valor
    # absoluto. Os dois convivem no legado e a melhoria foi **declinada pelo
    # usuário** (D-93, `improvements-log.md`). A entity **não** normaliza: quem
    # normalizasse aqui "consertaria" o D-93 sem ninguém ter decidido isso. Por
    # isso existe `original_balance_abs`, para o formulário.
    class RiskOperation < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :title, documentation: { type: 'String', desc: 'Cai para o título do portador quando vazio.' } do |o|
        o.title.to_s
      end

      expose :project_id, documentation: { type: 'String' }
      expose :company_id, documentation: { type: 'String' }
      expose :company_title, documentation: { type: 'String' } do |o|
        o.company&.title
      end
      expose :carrier_id, documentation: { type: 'String' }
      expose :carrier_title, documentation: { type: 'String' } do |o|
        o.carrier&.title
      end

      expose :operation_type_id, documentation: { type: 'String' }
      expose :operation_type_title, documentation: { type: 'String' } do |o|
        o.operation_type&.title
      end
      expose :operation_subtype_id, documentation: { type: 'String' }
      # **FE-250** — a coluna "Tipo" da lista mostra o **subtipo**, não o tipo:
      # é o subtipo que decide o bucket (liquidável × pré) no painel.
      expose :operation_subtype_title, documentation: { type: 'String' } do |o|
        o.operation_subtype&.title
      end
      expose :has_pre_faturamento,
             documentation: { type: 'Boolean', desc: 'Do TIPO. Decide se as datas e a aba PRORROGAÇÕES existem (FE-256/FE-264).' } do |o|
        o.operation_type&.has_pre_faturamento || false
      end
      expose :is_pre, documentation: { type: 'Boolean', desc: 'Do SUBTIPO. Decide se o botão "Transferir" existe (FE-272).' } do |o|
        o.operation_subtype&.is_pre || false
      end

      expose :risk_control_id, documentation: { type: 'String', desc: 'O limite consumido. NOT NULL.' }
      expose :contract_number, documentation: { type: 'String' } do |o|
        o.contract_number.to_s
      end

      expose :issue_date, documentation: { type: 'Date', desc: 'Nula APENAS no par estático.' }
      expose :due_date, documentation: { type: 'Date', desc: 'Nula APENAS no par estático.' }
      expose :original_due_date, documentation: { type: 'Date' }

      expose :operation_value, documentation: { type: 'String', desc: 'Capital. Decimal(14,2).' }
      expose :original_balance,
             documentation: { type: 'String', desc: 'Saldo inicial, gravado NEGATIVO (DEC-01). O detalhe exibe assim mesmo.' }
      expose :original_balance_abs,
             documentation: { type: 'String', desc: 'O mesmo valor em módulo — é o que o FORMULÁRIO edita.' } do |o|
        o.original_balance&.abs
      end
      expose :balance,
             documentation: { type: 'String', desc: 'Cache do saldo após o último movimento. Reescrito a cada save.' }
      expose :agreed_rate, documentation: { type: 'String', desc: 'Decimal(7,4), em %.' }

      expose :observation, documentation: { type: 'String' } do |o|
        o.observation.to_s
      end

      expose :is_on_variable, documentation: { type: 'Boolean' }
      # **DEC-35** — `is_ended` é RÓTULO. Não bloqueia movimento, não bloqueia
      # prorrogação e **não** retira a operação de `operations_on`: encerrada
      # continua consumindo limite e continua faturável.
      expose :is_ended, documentation: { type: 'Boolean', desc: 'Rótulo. Não tem consequência (DEC-35 / T-D4).' }
      expose :is_static, documentation: { type: 'Boolean', desc: 'Par pré/antecipação aberto pelo limite (B-08).' }

      expose :original_id, documentation: { type: 'String', desc: 'A RAIZ da cadeia de renovações, não o elo anterior.' }
      expose :pair_id, documentation: { type: 'String' }
      expose :receivable_id, documentation: { type: 'String', desc: 'Borderô que originou a operação (S6).' }
      expose :receipt_id, documentation: { type: 'String', desc: 'Recibo que a faturou (S6). Preenchido = não pode excluir.' }

      # **FE-250** — as contagens da lista.
      #
      # ### `nil` e `0` NÃO são a mesma coisa aqui, e confundi-los é um N+1
      #
      # As três contagens vêm de `group(...).count` no endpoint, que **omite** as
      # chaves com zero. Escrever `options[:extension_counts]&.fetch(o.id, nil) || o.extensions.size`
      # parece defensivo e é o contrário: para toda operação **sem** prorrogação
      # o `nil` cai no `||` e dispara uma consulta por linha — 50 linhas, 50
      # consultas, justamente no caso mais comum.
      #
      # O critério certo é a **presença do hash**: se o chamador passou as
      # contagens, ausência significa **zero**; se não passou (o `show`, por
      # exemplo), aí sim vale a associação.
      expose :extensions_count, documentation: { type: 'Integer' } do |o, options|
        contagem(options[:extension_counts], o) { o.extensions.size }
      end
      expose :renewals_count, documentation: { type: 'Integer', desc: 'Elos da cadeia, quando esta é a raiz.' } do |o, options|
        contagem(options[:renewal_counts], o) { 0 }
      end
      expose :movements_count, documentation: { type: 'Integer' } do |o, options|
        contagem(options[:movement_counts], o) { o.movements.size }
      end

      expose :created_at, documentation: { type: 'DateTime' }
      expose :updated_at, documentation: { type: 'DateTime' }

      private

      def contagem(mapa, registro)
        return mapa.fetch(registro.id, 0) if mapa

        yield
      end
    end
  end
end

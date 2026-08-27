# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `renegotiations` (legado) -> `Renegotiation` (ai9). **S9 / DB-194, DB-197.**
      #
      # ⚠ **DEC-102 — a CARGA ficou para depois da apresentação; o CONVERSOR não.**
      # Escrevê-lo agora, com a regra na cabeça, custa pouco; escrevê-lo daqui a
      # dois meses custa reaprender o domínio. Ele roda em dry-run e conta.
      #
      # ## Os três renomeados de 29/04/2022 (DEC-94 / Q-B31)
      #
      # Um deles é desta tabela: `total_value -> installments_main_value`. **O que
      # importa não é o nome, é a semântica:** `total_value` era *"R$ Total da
      # dívida"* e virou *"soma do principal das parcelas"*. Qualquer relatório
      # antigo que somasse essa coluna passou a somar outra coisa **desde 2022**, e
      # isso independe da migração. A origem já vem com o nome novo (a migration do
      # legado renomeou a coluna), então aqui é cópia direta — a nota fica
      # registrada para o caso de aparecer divergência histórica na conferência.
      #
      # ## Os agregados vêm COPIADOS, não recalculados
      #
      # Deliberado, e é o **DEC-30**: o painel do ai9 tem de bater com o do legado
      # no dia do cutover. Recalcular na carga produziria números **melhores** e
      # **diferentes** — e a primeira conversa seria "o sistema novo mudou meus
      # totais". A reconciliação (`Renegotiations::AggregateService.recalculate!`)
      # é passo separado, do `fixups.rb`, rodado quando o cliente decidir.
      #
      # A ÚNICA exceção é `state`: ele é copiado como está, inclusive quando o
      # legado gravou "Pago" numa renegociação que o ai9 chamaria de
      # "Inconsistente" (**D-45**). Corrigir na carga esconderia a diferença; o
      # recálculo posterior a revela, com o cliente sabendo.
      class Renegotiations < Base
        def self.source_table = 'renegotiations'
        def self.target_model = 'Renegotiation'
        def self.requires = %w[Renegotiation Project Provider Company]
        def self.owner_slice = 'S9'

        def self.references = {
          'project_id' => 'projects',
          'provider_id' => 'providers',
          'company_id' => 'companies'
        }

        # `has_safegold_management` é `integer` na origem (D-30, Q-B32): carimbo
        # copiado na criação e nunca ressincronizado.
        def self.booleans = %w[has_safegold_management]

        def self.uniques = [%w[project_id integration_key]]

        # As somas que a reconciliação confere por ano — é onde erro de cast e de
        # SINAL aparece. `pending_main_value` entra de propósito: ele PODE ser
        # negativo (Q-B22), e um cast que zerasse o negativo passaria despercebido
        # numa amostra.
        def self.sums = %w[
          total_debt original_value main_value paid_value remaining_value
          pending_main_value installments_main_value
        ]

        def self.year_column = 'renegotiation_date'

        # Colunas que o model do ai9 deriva na gravação e que por isso não se
        # comparam literalmente com a origem.
        # `attachments_count` entra aqui porque passou a ser derivado pelo
        # `counter_cache` em vez de copiado — ver o comentário no `convert`.
        def self.derived = %w[provider_name correct_value title integration_key attachments_count]

        # rubocop:disable Metrics/MethodLength
        def convert(row)
          {
            project_id: ref('projects', row['project_id']),
            provider_id: ref('providers', row['provider_id']),
            company_id: ref('companies', row['company_id']),

            title: row['title'].presence || row['provider_name'],
            provider_name: row['provider_name'],
            kind: row['kind'],
            integration_key: row['integration_key'],
            renegotiation_date: row['renegotiation_date'],
            observation: row['observation'],
            origin: row['origin'],
            monetary_correction: row['monetary_correction'],
            has_safegold_management: row['has_safegold_management'],

            original_value: Values.to_decimal(row['original_value']),
            original_pending_value: Values.to_decimal(row['original_pending_value']),
            additional_value: Values.to_decimal(row['additional_value']),
            total_debt: Values.to_decimal(row['total_debt']),
            # `desagio_value` e `total_value_with_desagio` NAO EXISTEM na origem —
            # conferido no `information_schema` contra o dump de producao. Sao campos
            # do ai9, e o conversor os lia como se viessem do legado: `row[...]` dava
            # nil, `to_decimal(nil)` devolvia nil, e a coluna e `null: false`. A carga
            # morria com `NotNullViolation`, que passa POR BAIXO do rescue novo do
            # motor — ele coleta `RecordInvalid` (validacao do model), nao violacao de
            # restricao do BANCO.
            #
            # Zero e a leitura honesta: as renegociacoes do legado nao registravam
            # desagio. Nao e "desconhecido" (que seria nulo, como a tarifa da DEC-120)
            # — e ausencia do conceito na origem.
            desagio_value: 0,
            correct_value: Values.to_decimal(row['correct_value']),

            interest_rate_correction: row['interest_rate_correction'].to_f,
            grace_period: row['grace_period'].to_i,
            operation_interest_rate: row['operation_interest_rate'].to_f,

            # --- agregados, COPIADOS (ver o cabeçalho) ---
            installments_main_value: Values.to_decimal(row['installments_main_value']),
            installments_interest_value: Values.to_decimal(row['installments_interest_value']),
            installments_main_value_with_interest: Values.to_decimal(row['installments_main_value_with_interest']),
            installments_monetary_correction_value:
              Values.to_decimal(row['installments_monetary_correction_value']),
            installments_main_value_with_interest_cm:
              Values.to_decimal(row['installments_main_value_with_interest_cm']),
            main_value: Values.to_decimal(row['main_value']),
            paid_value_with_interest_cm: Values.to_decimal(row['paid_value_with_interest_cm']),
            late_payment_value: Values.to_decimal(row['late_payment_value']),
            paid_value: Values.to_decimal(row['paid_value']),
            pending_main_value: Values.to_decimal(row['pending_main_value']),
            remaining_value: Values.to_decimal(row['remaining_value']),
            paid_percent: row['paid_percent'].to_f,
            # Mesmo caso: coluna do ai9, ausente na origem. Sem desagio registrado,
            # o total com desagio e o proprio total da divida.
            total_value_with_desagio: Values.to_decimal(row['total_debt']),
            current_installment_value: Values.to_decimal(row['current_installment_value']),
            current_value: Values.to_decimal(row['current_value']),

            installments_count: row['installments_count'].to_i,
            paid_installments: row['paid_installments'].to_i,
            overdue_installments: row['overdue_installments'].to_i,
            due_installments: row['due_installments'].to_i,
            first_due_date: row['first_due_date'],
            last_due_date: row['last_due_date'],
            state: row['state'],

            # **`attachments_count` NÃO é copiado — de propósito.**
            #
            # `RenegotiationAttachment belongs_to :renegotiation` declara
            # `counter_cache: :attachments_count`: o Rails INCREMENTA a coluna a
            # cada anexo que entra. Copiar o valor da origem e depois carregar
            # os anexos soma as duas coisas, e o contador sai exatamente
            # DOBRADO. Medido nesta base: 35 renegociações erradas, contador
            # somando 88 contra 44 anexos reais.
            #
            # Ninguém percebeu porque a coluna é `null: false` com default 0 e
            # dobrar não viola nada: a carga passava, a reconciliação de
            # CONTAGEM passava (as 44 linhas de anexo estão lá), e só a amostra
            # campo a campo mostrou. Contador derivado não se copia — deixa-se
            # derivar, e confere-se depois.
            #
            # `RenegotiationAttachments.post_load!` reconcilia ao fim, para o
            # caso de a base já ter valor de uma carga anterior.

            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end
        # rubocop:enable Metrics/MethodLength

        # As anomalias que a auditoria de DB-199 procura, no nível da linha.
        def anomalies(row)
          achados = []
          if row['attachments_count'].nil?
            achados << "renegotiation ##{row['id']}: attachments_count NULO (DB-195)"
          end
          if row['state'].present? && ::Renegotiation::STATES.exclude?(row['state'])
            achados << "renegotiation ##{row['id']}: estado fora do domínio (#{row['state'].inspect})"
          end
          if row['kind'].present? && ::Renegotiation::KINDS.exclude?(row['kind'])
            achados << "renegotiation ##{row['id']}: tipo fora do domínio (#{row['kind'].inspect})"
          end
          achados << "renegotiation ##{row['id']}: sem empresa (company_id nulo)" if row['company_id'].blank?
          achados
        end
      end
    end
  end
end

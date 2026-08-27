# frozen_string_literal: true

module Demo
  module Writers
    # Renegociações e parcelas. Chaves naturais: `(project_id, integration_key)` e
    # `(renegotiation_id, due_date)` — os dois índices únicos que a S9 declara.
    #
    # ### O que este escritor escreve, e o que ele **deixa o sistema calcular**
    #
    # Ele escreve o **contrato**: fornecedor, empresa, datas, taxa, valores
    # negociados e as parcelas. Os ~20 agregados da renegociação (o "R$ Pago", o
    # "R$ A Pagar", o percentual, as contagens, o estado e o valor presente)
    # **não** são escritos: quem os calcula é `Renegotiations::AggregateService`,
    # o cálculo único da S9 (contrato C2), chamado ao fim de cada renegociação.
    #
    # É o que `demo-seed-design.md` §7 manda fazer onde a fatia dona já entregou
    # o serviço — e aqui o ganho é concreto e verificável: o rodapé da tela passa
    # a bater com a lista **pela mesma conta que bate em produção**, e não porque
    # o razão e o serviço chegaram por acaso ao mesmo número. Quando a S9 mudar a
    # fórmula, o seed acompanha sozinho.
    #
    # Os derivados de cada parcela saem de `Renegotiations::Formulas.installment`
    # pelo mesmo motivo: `saldo` (pt-BR, negativo) e `pending_value` (com piso em
    # zero) coexistem com semânticas diferentes, e reimplementar essa assimetria
    # aqui seria criar a segunda verdade que a S9 passou a fatia inteira
    # eliminando.
    class Renegotiations < Base
      def self.requires = %w[Renegotiation RenegotiationInstallment RenegotiationPayment Provider]
      def self.owner_slice = 'S9'

      def call
        providers = index_providers

        ledger.renegotiations.each do |renegotiation|
          project = project_for(renegotiation.client)
          company = companies_by_key[renegotiation.company.key]
          provider = providers[[renegotiation.client.slug, renegotiation.provider_name]]
          next if project.nil? || company.nil? || provider.nil?

          record = upsert!(::Renegotiation,
                           find_by: { project_id: project.id,
                                      integration_key: integration_key(renegotiation) },
                           attributes: attributes_for(renegotiation, company, provider))

          write_installments!(record, renegotiation)
          recalculate!(record)
        end
      end

      private

      # **A mesma derivação do model** (`derivar_chave_de_integracao`): a chave
      # nasce do nome do fornecedor. Escrevê-la aqui, em vez de deixar o model
      # derivá-la, é o que permite reencontrar a linha na segunda execução — a
      # chave natural precisa ser conhecida ANTES de o registro existir.
      def integration_key(renegotiation)
        I18n.transliterate(renegotiation.provider_name).downcase.gsub(' ', '_')
      end

      def index_providers
        ::Provider.where(project_id: projects_by_slug.values.map(&:id))
                  .index_by { |p| [slug_of(p.project_id), p.title] }
      end

      def slug_of(project_id)
        @slug_of ||= projects_by_slug.to_h { |slug, project| [project.id, slug] }
        @slug_of[project_id]
      end

      def attributes_for(renegotiation, company, provider)
        {
          provider_id: provider.id,
          company_id: company.id,
          title: renegotiation.title,
          # `provider_name` é carimbo: o model o copia de `provider.title` em
          # toda gravação. Mandá-lo aqui só para o model reescrever com o mesmo
          # texto seria propor uma mudança inexistente.
          kind: renegotiation.kind,
          renegotiation_date: renegotiation.renegotiation_date,
          operation_interest_rate: renegotiation.operation_interest_rate,
          original_value: renegotiation.original_value,
          original_pending_value: renegotiation.original_pending_value,
          additional_value: renegotiation.additional_value,
          total_debt: renegotiation.total_debt,
          desagio_value: 0,
          monetary_correction: 'IPCA',
          origin: 'Fornecedor'
          # `correct_value`, `state` e os agregados: ver o cabeçalho — são do
          # `AggregateService`.
        }
      end

      # As parcelas de uma renegociação compartilham **um** `batch_token`: é ele
      # que agrupa o lote na tela (BE-217). Determinístico a partir da chave do
      # razão, e não `SecureRandom`, porque um token novo a cada execução faria a
      # segunda rodada reportar 34 lotes "atualizados" sem nenhuma mudança real.
      def write_installments!(record, renegotiation)
        token = batch_token_for(renegotiation)

        renegotiation.installments.each do |installment|
          derived = ::Renegotiations::Formulas.installment(
            main_value: installment.main_value,
            interest_value: interest_of(installment),
            monetary_correction_value: 0,
            paid_value: installment.paid_value
          )

          row = upsert!(::RenegotiationInstallment,
                        find_by: { renegotiation_id: record.id, due_date: installment.due_date },
                        attributes: {
                          project_id: record.project_id,
                          number: installment.number,
                          main_value: installment.main_value,
                          interest_value: interest_of(installment),
                          monetary_correction_value: 0,
                          batch_token: token,
                          **derived
                        })

          write_payment!(record, row, installment)
        end
      end

      # **A parcela paga tem pagamento.** Sem esta linha o "R$ Pago" do agregado
      # sai zerado — o `AggregateService` soma os PAGAMENTOS, não o campo da
      # parcela — e a demonstração mostra doze parcelas quitadas com R$ 0,00
      # pagos, além de uma aba de pagamentos vazia. Um pagamento por parcela,
      # integral e sem mora.
      def write_payment!(renegotiation, installment_row, installment)
        return unless installment.is_paid

        upsert!(::RenegotiationPayment,
                find_by: { renegotiation_installment_id: installment_row.id, payment_number: 1 },
                attributes: {
                  renegotiation_id: renegotiation.id,
                  project_id: renegotiation.project_id,
                  date: installment.due_date,
                  days_late: 0,
                  installment_paid_value_with_interest_cm: installment.paid_value,
                  late_payment_value: 0,
                  total_paid_value: installment.paid_value
                })
      end

      # O razão guarda o total da parcela; os juros são a diferença para o
      # principal. Uma conta, não um segundo sorteio.
      def interest_of(installment)
        Support::Money.round2(installment.total_value - installment.main_value)
      end

      # UUID determinístico (v5, namespace do DNS) a partir da chave do razão.
      def batch_token_for(renegotiation)
        Digest::UUID.uuid_v5(Digest::UUID::DNS_NAMESPACE, "demo-seed:#{renegotiation.key}")
      end

      # `broadcast: false`: recalcular 34 renegociações não é motivo para
      # publicar 34 mensagens num canal que ninguém está ouvindo durante um seed.
      def recalculate!(record)
        ::Renegotiations::AggregateService.recalculate!(record, broadcast: false)
      end
    end
  end
end

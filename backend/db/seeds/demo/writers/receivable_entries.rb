# frozen_string_literal: true

module Demo
  module Writers
    # Os borderôs (`receivable_entries`). Chave natural: `(project_id, nro_bordero)`.
    #
    # **Os nomes de coluna são em pt-BR de propósito.** A decisão **D-G** manteve
    # `nro_bordero`, `valor_bruto`, `vlr_bruto_recusado`, `prz_med_pond_emp` e
    # companhia verbatim nas tabelas transacionais — exceção explícita e
    # documentada à convenção de identificadores em inglês. Este escritor é onde
    # isso fica visível, e é por isso que a tradução mora aqui e não no razão.
    #
    # `nro_bordero` é **string** para preservar zeros à esquerda.
    # ## As três colunas que a S6 passou a exigir, e o que elas custaram
    #
    # Na medição de 26/08/2026 este escritor **falhava inteiro** — 2.706 borderôs
    # de fora, nenhuma lista da demonstração passando de uma página. O erro era
    # `Autor não pode ficar em branco, Situação não está incluído na lista`: a S6
    # entregou `validates :user_id, presence: true` (BE-182 — o autor é o da
    # sessão, nunca o do corpo), `cst_efetivo_acordado` obrigatório e o domínio
    # fechado `ok`/`difference` no lugar do texto pt-BR `"OK"` do legado
    # (`Entry::STATUSES`). O razão gravava `status: 'OK'` — o rótulo, não o valor.
    #
    # Duas colunas também estavam com o nome errado e eram descartadas em
    # silêncio pelo `assign` (`tarifas_advalorem` em vez de `tarifas_ad_valorem`,
    # `valor_liq_correto` em vez de `calc_valor_liq_correto`).
    #
    # ## Os ~30 derivados saem do `Receivables::Calculator`, não daqui
    #
    # O borderô tem trinta colunas calculadas — custo efetivo por prazo médio,
    # taxas de desconto nominal, multiplicadores. Preenchê-las à mão seria uma
    # **segunda** implementação da conta que o contrato C2 existe para manter
    # única, e a tela ordena por três delas (`cet`, `cetsf`): deixá-las nulas
    # daria coluna em branco na lista.
    #
    # O escritor monta as tarifas em memória, chama o calculador **uma vez** com
    # a alíquota de IOF vigente na data do borderô e grava o resultado. É a mesma
    # sequência do `Receivables::WriteService` — sem o passo 5, porque a operação
    # de risco deste seed é escrita pelo próprio razão, com a história de
    # movimentos que ela precisa ter.
    class ReceivableEntries < Base
      def self.requires = %w[ReceivableEntry ReceivableTax MovementKind IofRate]
      def self.owner_slice = 'S6'

      # As quatro tarifas de um borderô, pela chave de integração do
      # `MovementKind` — nunca pelo título, que é editável na tela (DC-22).
      TAX_KINDS = { desagio: 'desagio', advalorem: 'advalorem',
                    iof: 'iof', outras: 'outras_despesas' }.freeze

      def call
        catalogs = load_catalogs
        types = defined?(::RiskOperationType) ? ::RiskOperationType.all.index_by(&:integration_key) : {}
        kinds = movement_kinds
        author_id = demo_author&.id

        ledger.borderos.each do |bordero|
          project = project_for(bordero.client)
          company = companies_by_key[bordero.company.key]
          carrier = carrier_for(bordero.carrier)
          next if project.nil? || company.nil? || carrier.nil?

          taxes = tax_rows(bordero, kinds)
          entry = upsert!(::ReceivableEntry,
                          find_by: { project_id: project.id, nro_bordero: bordero.nro },
                          attributes: attributes_for(bordero, company, carrier, catalogs, types, author_id)
                                      .merge(derived_for(bordero, taxes)))

          write_taxes!(entry, taxes, kinds)
        end
      end

      private

      # O calculador é **função pura** e não conhece `ReceivableTax`: ele recebe
      # os classificadores já resolvidos. A alíquota de IOF vem de
      # `IofRate.effective_on(data)` — é o que mantém o motor puro e o que
      # permite o golden fixar a alíquota (BE-160 / D-15).
      def derived_for(bordero, taxes)
        input = ::Receivables::Calculator::Input.new(
          valor_bruto: bordero.valor_bruto, vlr_bruto_recusado: bordero.vlr_bruto_recusado,
          qtd_titulos: bordero.qtd_titulos, qtd_recusada: bordero.qtd_recusada,
          prz_med_pond_emp: bordero.prz_med_pond_emp, prz_med_pond_bco: bordero.prz_med_pond_bco,
          float_acordado: bordero.float_acordado,
          cst_efetivo_acordado: bordero.cst_efetivo_acordado,
          recompra: 0, retencao: 0, fomento: 0, outros: 0,
          taxes: taxes.map do |row|
            ::Receivables::Calculator::Tax.new(
              value: row[:value], is_advalorem: row[:is_advalorem],
              is_desagio: row[:is_desagio], is_iof: row[:is_iof]
            )
          end
        )

        ::Receivables::Calculator.call(input, iof_rate: ::IofRate.effective_on(bordero.date))
      end

      def tax_rows(bordero, kinds)
        [
          { key: :desagio, value: bordero.tarifa_desagio },
          { key: :advalorem, value: bordero.tarifa_advalorem },
          { key: :iof, value: bordero.tarifa_iof },
          { key: :outras, value: bordero.tarifa_outras }
        ].filter_map do |row|
          kind = kinds[row[:key]]
          next if kind.nil?

          row.merge(movement_kind: kind, is_advalorem: kind.is_advalorem,
                    is_desagio: kind.is_desagio, is_iof: kind.is_iof)
        end
      end

      # A tarifa é **linha de verdade**, não só um agregado na coluna do pai: sem
      # ela a aba de tarifas do borderô abre vazia enquanto o rodapé mostra
      # R$ 12 mil de custo — que é exatamente o rodapé que não bate.
      def write_taxes!(entry, taxes, _kinds)
        taxes.each do |row|
          upsert!(::ReceivableTax,
                  find_by: { receivable_entry_id: entry.id, movement_kind_id: row[:movement_kind].id },
                  attributes: { value: row[:value] })
        end
      end

      def movement_kinds
        return {} unless defined?(::MovementKind)

        found = ::MovementKind.where(integration_key: TAX_KINDS.values).index_by(&:integration_key)
        missing = TAX_KINDS.values - found.keys
        raise "Tipos de movimentação ausentes: #{missing.join(', ')} — rode `rake reference:seed`" if missing.any?

        TAX_KINDS.transform_values { |key| found[key] }
      end

      def attributes_for(bordero, company, carrier, catalogs, types, author_id)
        {
          company_id: company.id,
          carrier_id: carrier.id,
          wallet_id: catalogs[:wallets][bordero.wallet]&.id,
          receivable_kind_id: catalogs[:kinds][bordero.receivable_kind]&.id,
          resource_source_id: catalogs[:sources][bordero.resource_source]&.id,
          risk_operation_type_id: types[bordero.control.modality.to_s]&.id,
          date: bordero.date,
          description: "Borderô #{bordero.nro} — #{bordero.carrier.title}",
          qtd_titulos: bordero.qtd_titulos,
          qtd_recusada: bordero.qtd_recusada,
          qtd_final: bordero.qtd_final,
          valor_bruto: bordero.valor_bruto,
          vlr_bruto_recusado: bordero.vlr_bruto_recusado,
          vlr_bruto_final: bordero.vlr_bruto_final,
          prz_med_pond_emp: bordero.prz_med_pond_emp,
          prz_med_pond_bco: bordero.prz_med_pond_bco,
          float_acordado: bordero.float_acordado,
          # **`cst_efetivo_acordado` é digitado, não derivado** — é o custo que a
          # mesa negociou, e é dele que sai `calc_valor_liq_correto`. Sem ele o
          # model recusa a gravação.
          cst_efetivo_acordado: bordero.cst_efetivo_acordado,
          nominal_tax: bordero.nominal_tax,
          # As quatro deduções do borderô. O seed não usa nenhuma delas (nenhum
          # cliente da história opera com recompra ou retenção), mas elas entram
          # explicitamente: o calculador divide por elas e `nil` viraria zero por
          # acidente, não por decisão.
          recompra: 0.0, retencao: 0.0, fomento: 0.0, outros: 0.0,
          # `user_id` é o autor, e a S6 o exige (BE-182). O da SESSÃO, na tela;
          # aqui o Admin do elenco.
          user_id: author_id,
          has_safegold_management: true
        }
      end

      # Catálogos globais são de `OPS-540` (S3). O razão os referencia por
      # **título**, e título que não resolve **estoura aqui**, nomeando o que
      # faltou.
      #
      # A versão anterior deixava `nil` passar "para não impedir a gravação" — e
      # o efeito foi o oposto: `receivable_kind_id` é `null: false` com validação
      # de presença, então o borderô era recusado de qualquer jeito, e a
      # mensagem falava de um campo em branco em vez do título que não existe no
      # catálogo. Falhar no lugar certo é a diferença entre trinta segundos e uma
      # hora de investigação.
      def load_catalogs
        {
          wallets: index_of('Wallet', Ledger::Receivables::WALLETS),
          kinds: index_of('ReceivableKind', Ledger::Receivables::RECEIVABLE_KINDS),
          sources: index_of('ResourceSource', Ledger::Receivables::RESOURCE_SOURCES)
        }
      end

      def index_of(model_name, expected)
        return {} unless Object.const_defined?(model_name)

        found = Object.const_get(model_name).where(title: expected).index_by(&:title)
        missing = expected - found.keys
        if missing.any?
          raise "#{model_name}: título ausente no catálogo — #{missing.join(', ')}. " \
                'Rode `rake reference:seed` ou alinhe o razão ao catálogo entregue.'
        end

        found
      end
    end
  end
end

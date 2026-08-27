# frozen_string_literal: true

require 'rails_helper'

# S7 / **BE-259, BE-260, BE-277** — goldens `M3` (renovação) e `M4` (prorrogação).
#
# ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
#
# `create_risk_operations` e `create_risk_operation_extensions` estão entre as
# **24 migrations que nunca subiram** (`analise-dump-producao.md` §1): a última
# migration aplicada em produção é de **25/05/2022** e o sistema rodou em uso
# até **31/05/2025**. **Nenhuma renovação e nenhuma prorrogação existiram.**
#
# Estes goldens travam a leitura de
# `../sfg/app/models/risk_operation.rb:113-139`,
# `../sfg/app/controllers/pub/risk_operations_controller.rb:86-113` e
# `../sfg/app/models/risk_operation_extension.rb`. **Fonte, não oráculo.**
RSpec.describe 'Risk::RenewalService e Risk::ExtensionService' do
  let!(:cenario) { cenario_m1 }
  let(:operacao) { cenario[:operation] }
  let(:projeto) { cenario[:project] }
  let(:autor) { cenario[:user] }

  # =====================================================================
  # Golden M3 — renovação
  # =====================================================================
  describe 'golden M3 — renovação (BE-259 / BE-260)' do
    let(:hoje) { Date.new(2026, 5, 20) }

    describe '#prepare (BE-259) — preserva o PRAZO em dias' do
      it 'sugere 18/09/2026 para 01/03→30/06 renovada em 20/05' do
        # `risk_operations_controller.rb:91-93`:
        #   issue_date   = hoje
        #   date_interval = hoje − issue_date_original          → 80 dias
        #   due_date     = due_date_original + date_interval    → 18/09/2026
        resultado = Risk::RenewalService.prepare(project: projeto, operation_id: operacao.id,
                                                 issue_date: hoje)

        expect(resultado[:status]).to eq(200)
        expect(resultado[:data][:elapsed_days]).to eq(80)
        expect(resultado[:data][:issue_date]).to eq(Date.new(2026, 5, 20))
        expect(resultado[:data][:due_date]).to eq(Date.new(2026, 9, 18))
      end

      it 'devolve 404 para id inexistente — no legado é 500' do
        resultado = Risk::RenewalService.prepare(project: projeto,
                                                 operation_id: SecureRandom.uuid)
        expect(resultado[:status]).to eq(404)
      end
    end

    describe '#create (BE-260)' do
      let!(:resultado) do
        Risk::RenewalService.create(project: projeto, operation_id: operacao.id,
                                    issue_date: hoje, due_date: Date.new(2026, 9, 18),
                                    actor: autor)
      end
      let(:nova) { resultado[:data] }

      it 'copia os 13 campos e força is_ended = false' do
        expect(resultado[:status]).to eq(201)
        expect(nova.title).to eq(operacao.title)
        expect(nova.operation_type_id).to eq(operacao.operation_type_id)
        expect(nova.operation_subtype_id).to eq(operacao.operation_subtype_id)
        expect(nova.company_id).to eq(operacao.company_id)
        expect(nova.carrier_id).to eq(operacao.carrier_id)
        expect(nova.contract_number).to eq(operacao.contract_number)
        expect(nova.operation_value).to eq(operacao.operation_value)
        expect(nova.agreed_rate).to eq(operacao.agreed_rate)
        expect(nova.observation).to eq(operacao.observation)
        expect(nova.is_on_variable).to eq(operacao.is_on_variable)
        expect(nova.receivable_id).to eq(operacao.receivable_id)
        expect(nova.original_balance).to eq(operacao.original_balance)
        expect(nova.is_ended).to be(false)
      end

      it 'encadeia SEMPRE na raiz, não no elo clicado' do
        # `risk_operation.rb:117` — `original.original_id.blank? ? original.id : original.original_id`.
        expect(nova.original_id).to eq(operacao.id)

        segunda = Risk::RenewalService.create(project: projeto, operation_id: nova.id,
                                              issue_date: Date.new(2026, 7, 1), actor: autor)[:data]
        expect(segunda.original_id).to eq(operacao.id)
      end

      # -----------------------------------------------------------------
      # ⚠ DEC-35 ANULA A TAREFA 6.3 DO `tasks.md` — leia antes de "consertar"
      # -----------------------------------------------------------------
      it 'NÃO encerra a operação original — DEC-35 (o tasks.md pedia o contrário)' do
        # O `tasks.md` e o `proposal.md` (Phase 2) pediam **IMP-R1**: renovar
        # encerra a original, corrigindo o D-94. A **DEC-35 (25/08/2026)**
        # decidiu **depois** que o ciclo de vida do legado é REPLICADO:
        #
        #   "Renovar NÃO encerra a original. As duas operações ficam vivas e as
        #    duas consomem limite de risco ao mesmo tempo. […] Um teste que
        #    exija encerramento automático está errado contra esta DEC."
        #
        # O orquestrador levantou a objeção antes de perguntar e o usuário
        # reafirmou replicar. Vale o DEC-30.
        expect(operacao.reload.is_ended).to be(false)
      end

      it 'a exposição em 01/06/2026 conta as DUAS operações — consequência da DEC-35' do
        # As janelas se sobrepõem (01/03→30/06 e 20/05→18/09) e nenhuma está
        # encerrada, então `operations_on` traz as duas. **Não é regressão**:
        # é o D-94, declinado conscientemente. QA não deve abrir bug.
        vigentes = Risk::Calculator.operations_on(cenario[:control], Date.new(2026, 6, 1))
        expect(vigentes).to include(operacao, nova)
        expect(vigentes.count).to eq(2)
      end

      it 'a nova nasce com o próprio movimento de liberação (BE-264)' do
        expect(nova.movements.count).to eq(1)
        expect(nova.movements.first.movement_type.integration_key).to eq(RiskMovementType::RELEASE_KEY)
        expect(nova.reload.balance).to eq(0.00)
      end

      # -----------------------------------------------------------------
      # A leitura da fonte que o design.md errou
      # -----------------------------------------------------------------
      it 'grava original_due_date = o vencimento NOVO, e não o do elo anterior' do
        # O `design.md` desta fatia diz, no golden M3, que `original_due_date`
        # da nova é 30/06/2026 ("o vencimento da que foi renovada"). **Não é o
        # que o código de 2022 faz.** `create_renovation` passa
        # `original_due_date: original.due_date` (`:134`), e logo o
        # `before_validation on: [:create]` do próprio model sobrescreve com
        # `self.due_date` (`:23`) — o vencimento NOVO.
        #
        # Pela DEC-103b ("espelhar o código de 2022 como está, sem corrigir o
        # que parecer errado") o comportamento replicado é o do callback.
        expect(nova.original_due_date).to eq(Date.new(2026, 9, 18))
      end

      it 'recusa vencimento anterior à emissão — regra do tasks.md 6.3' do
        # Mais estrito que o `create` direto, e é deliberado: lá vale o BE-267
        # (Q-R7, "replicar as ausências"), porque há dado histórico a
        # preservar; aqui o caminho é novo e as duas datas são sugeridas pelo
        # servidor.
        r = Risk::RenewalService.create(project: projeto, operation_id: operacao.id,
                                        issue_date: Date.new(2026, 6, 1),
                                        due_date: Date.new(2026, 5, 1), actor: autor)
        expect(r[:status]).to eq(422)
      end
    end

    describe '#chain (FE-267)' do
      it 'devolve a raiz e todos os elos, em ordem de emissão' do
        a = Risk::RenewalService.create(project: projeto, operation_id: operacao.id,
                                        issue_date: hoje, actor: autor)[:data]
        b = Risk::RenewalService.create(project: projeto, operation_id: a.id,
                                        issue_date: Date.new(2026, 7, 1), actor: autor)[:data]

        cadeia = Risk::RenewalService.chain(project: projeto, operation_id: b.id)[:data].to_a
        expect(cadeia.map(&:id)).to eq([operacao.id, a.id, b.id])
        # Consequência da DEC-35: todos os elos continuam abertos.
        expect(cadeia.map(&:is_ended)).to all(be(false))
      end
    end
  end

  # =====================================================================
  # Golden M4 — prorrogação
  # =====================================================================
  describe 'golden M4 — prorrogação (BE-277)' do
    it 'carimba original_due_date DA OPERAÇÃO, ignorando o valor do formulário' do
      # `risk_operation_extension.rb:5`.
      resultado = Risk::ExtensionService.create(
        project: projeto, operation_id: operacao.id,
        attrs: { new_due_date: Date.new(2026, 8, 31), observation: 'Acordo verbal' },
        actor: autor
      )

      expect(resultado[:status]).to eq(201)
      expect(resultado[:data].original_due_date).to eq(Date.new(2026, 6, 30))
      expect(resultado[:data].new_due_date).to eq(Date.new(2026, 8, 31))
    end

    it 'sobrescreve o vencimento da operação e reexecuta o recálculo' do
      # `:9-10` — `self.operation.due_date = self.new_due_date; self.operation.save`.
      Risk::ExtensionService.create(project: projeto, operation_id: operacao.id,
                                    attrs: { new_due_date: Date.new(2026, 8, 31) }, actor: autor)

      expect(operacao.reload.due_date).to eq(Date.new(2026, 8, 31))
      # A cadeia continua intacta — o recálculo rodou e produziu os mesmos saldos.
      expect(operacao.movements.order(:sequence).pluck(:balance)).to eq([0.00, 2_500.00, -27_500.00])
    end

    it 'recusa ENCURTAR o vencimento — no legado só o datepicker impedia' do
      # Por requisição direta o legado aplicava a data menor sem reclamar,
      # deixando movimentos legítimos fora da janela de BE-274.
      resultado = Risk::ExtensionService.create(
        project: projeto, operation_id: operacao.id,
        attrs: { new_due_date: Date.new(2026, 6, 15) }, actor: autor
      )

      expect(resultado[:status]).to eq(422)
      expect(resultado[:error]).to match(/não encurta prazo|posterior ao vencimento/i)
      expect(operacao.reload.due_date).to eq(Date.new(2026, 6, 30))
      expect(RiskOperationExtension.count).to eq(0)
    end

    it 'recusa a data IGUAL ao vencimento — prorrogação anda para a frente' do
      resultado = Risk::ExtensionService.create(
        project: projeto, operation_id: operacao.id,
        attrs: { new_due_date: Date.new(2026, 6, 30) }, actor: autor
      )
      expect(resultado[:status]).to eq(422)
    end

    it 'o log é IMUTÁVEL: não há update nem destroy expostos' do
      expect(Risk::ExtensionService).not_to respond_to(:update)
      expect(Risk::ExtensionService).not_to respond_to(:destroy)
    end

    it 'acumula, e a contagem é o que a coluna "Prorrogações" da lista mostra' do
      Risk::ExtensionService.create(project: projeto, operation_id: operacao.id,
                                    attrs: { new_due_date: Date.new(2026, 8, 31) }, actor: autor)
      Risk::ExtensionService.create(project: projeto, operation_id: operacao.id,
                                    attrs: { new_due_date: Date.new(2026, 10, 31) }, actor: autor)

      expect(operacao.reload.extensions.count).to eq(2)
      expect(operacao.due_date).to eq(Date.new(2026, 10, 31))
      expect(operacao.extensions.chronological.map(&:original_due_date))
        .to eq([Date.new(2026, 6, 30), Date.new(2026, 8, 31)])
    end

    it '#prepare devolve min_due_date = due_date + 1' do
      resultado = Risk::ExtensionService.prepare(project: projeto, operation_id: operacao.id)
      expect(resultado[:data][:min_due_date]).to eq(Date.new(2026, 7, 1))
    end

    it 'operação ENCERRADA continua prorrogável — DEC-35 / T-D4' do
      operacao.update!(is_ended: true)
      resultado = Risk::ExtensionService.create(project: projeto, operation_id: operacao.id,
                                                attrs: { new_due_date: Date.new(2026, 8, 31) }, actor: autor)
      expect(resultado[:status]).to eq(201)
    end
  end
end

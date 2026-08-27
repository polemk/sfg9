# frozen_string_literal: true

module Risk
  # S7 / **BE-259, BE-260** — a **renovação** de uma operação de risco.
  #
  # ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
  #
  # `create_risk_operations` está entre as **24 migrations que nunca subiram**
  # (`analise-dump-producao.md` §1): a última migration aplicada em produção é
  # de 25/05/2022 e o sistema rodou até 31/05/2025. **Nenhuma renovação existiu.**
  # A fonte é `../sfg/app/models/risk_operation.rb:113-139` e
  # `../sfg/app/controllers/pub/risk_operations_controller.rb:86-113`. O golden
  # `M3` trava a leitura dessa fonte — não um comportamento observado. Onde não
  # há produção, o teste tem uma **fonte**, não um **oráculo**.
  #
  # ## ⚠ A DEC-35 ANULA A TAREFA 6.3 DO `tasks.md`
  #
  # O `tasks.md` e o `proposal.md` desta fatia foram escritos no Phase 2 e pedem
  # **IMP-R1**: "a renovação **encerra** a operação original", corrigindo o
  # **D-94** (as duas consomem limite ao mesmo tempo). **A DEC-35 (25/08/2026)
  # decidiu o contrário, depois:**
  #
  # > *"**Renovar NÃO encerra a original.** As duas operações ficam vivas e as
  # > duas consomem limite de risco ao mesmo tempo. […] O golden test da S7
  # > trava os dois lados — inclusive o caso da renovação, que **deve** produzir
  # > duas operações ativas. **Um teste que exija encerramento automático está
  # > errado contra esta DEC.**"*
  #
  # O orquestrador levantou a objeção antes de perguntar (o `legacy-defects.md`
  # trazia o veredito "corrigir — a renovação em dobro é erro de exposição
  # financeira") e o usuário **reafirmou replicar**. Vale o DEC-30.
  #
  # **Consequência registrada:** a exposição em 01/06/2026 conta **duas**
  # operações enquanto as janelas se sobrepõem. Isso **não é regressão** e o QA
  # do Phase 4 não deve abrir bug — está no `improvements-log.md` como melhoria
  # **declinada**, não como esquecimento.
  #
  # ## O que a renovação faz
  #
  # | Grandeza | Regra | Fonte |
  # | -------- | ----- | ----- |
  # | `issue_date` | hoje (o formulário pode mudar) | `risk_operations_controller.rb:91` |
  # | `due_date` | `due_date_original + (hoje − issue_date_original)` — **preserva o prazo em dias** | `:92-93` |
  # | `original_id` | a **raiz** da cadeia: `original.original_id || original.id` | `risk_operation.rb:117` |
  # | `original_due_date` | o vencimento **da que foi renovada** | `:134` |
  # | `is_ended` da nova | **falso**, forçado | `:132` |
  # | `is_ended` da original | **inalterado** | **DEC-35** |
  #
  # São **13 campos copiados** (`:119-138`): título, tipo, projeto, empresa,
  # portador, contrato, `operation_value`, `agreed_rate`, observação,
  # `is_on_variable`, `receivable_id`, `operation_subtype_id`, `original_balance`.
  # `contract_number` é o 13.º; `user_id` vem de `current_user` e não conta como
  # cópia.
  class RenewalService
    class << self
      include ApiResponseHandler

      # ------------------------------------------------------------------
      # BE-259 — a prévia (o drawer "Renovar")
      # ------------------------------------------------------------------
      # Nada é gravado: monta em memória as duas datas sugeridas. No legado
      # `RiskOperation.where(id: …).first` seguido de `.id` dá **500** para id
      # inexistente (`:88-90`); aqui é **404**.
      #
      # **Golden `M3`:** original 01/03/2026 → 30/06/2026, renovada em
      # 20/05/2026 (80 dias decorridos) sugere vencimento **18/09/2026**.
      def prepare(project:, operation_id:, issue_date: nil)
        original = Risk::OperationService.find(project, operation_id)
        return not_found if original.nil?
        return sem_janela if original.is_static?

        nova_emissao = (issue_date.presence || Date.current).to_date
        prazo_decorrido = nova_emissao - original.issue_date

        { status: 200,
          data: {
            original_id: original.id,
            root_id: raiz_de(original),
            issue_date: nova_emissao,
            due_date: original.due_date + prazo_decorrido,
            elapsed_days: prazo_decorrido.to_i,
            original_due_date: original.due_date,
            title: original.title,
            operation_value: original.operation_value,
            agreed_rate: original.agreed_rate
          } }
      end

      # ------------------------------------------------------------------
      # BE-260 — a gravação
      # ------------------------------------------------------------------
      # **A original NÃO é encerrada** (DEC-35). O que a transação garante é que
      # a nova operação nasce inteira — com o movimento de "Liberação do
      # Recurso" do `after_create`, quando o tipo não tem pré-faturamento.
      #
      # **Uma regra mais estrita que a do `create`, e é deliberada
      # (`tasks.md` 6.3):** `due_date > issue_date` vale **aqui**. O `create`
      # direto continua permissivo por `BE-267`/Q-R7 ("replicar as ausências —
      # não recusar dado que hoje entra"), porque lá existe dado histórico a
      # preservar; a renovação é um caminho **novo**, com as duas datas
      # sugeridas pelo servidor, e uma cadeia com vencimento anterior à emissão
      # não corresponde a nada. A divergência está escrita para ninguém
      # "unificar" por engano numa direção não decidida.
      def create(project:, operation_id:, issue_date: nil, due_date: nil, actor: nil)
        original = Risk::OperationService.find(project, operation_id)
        return not_found if original.nil?
        return sem_janela if original.is_static?

        nova_emissao = (issue_date.presence || Date.current).to_date
        novo_vencimento = (due_date.presence || (original.due_date + (nova_emissao - original.issue_date))).to_date

        if novo_vencimento <= nova_emissao
          return { status: 422, error: 'O novo vencimento tem de ser posterior à nova emissão.' }
        end

        nova = nil
        RiskOperation.transaction do
          nova = RiskOperation.new(campos_copiados(original).merge(
                                     user_id: actor&.id || original.user_id,
                                     issue_date: nova_emissao,
                                     due_date: novo_vencimento,
                                     is_ended: false,
                                     original_id: raiz_de(original)
                                   ))
          raise ActiveRecord::Rollback unless nova.save
        end

        return unprocessable(nova) if nova.nil? || !nova.persisted?

        { status: 201, data: nova.reload }
      rescue RiskMovementType::MissingFunctionalType => e
        { status: 422, error: e.message }
      end

      # A cadeia de renovações a partir da RAIZ — o que `RenewalsCard` (FE-267)
      # mostra. Inclui a própria raiz, porque a cadeia começa nela.
      def chain(project:, operation_id:)
        operation = Risk::OperationService.find(project, operation_id)
        return not_found if operation.nil?

        raiz_id = raiz_de(operation)
        escopo = RiskOperation.for_project(project)
                              .where('risk_operations.id = :r OR risk_operations.original_id = :r', r: raiz_id)
                              .order(issue_date: :asc, created_at: :asc)

        { status: 200, data: escopo }
      end

      private

      # `:117` — **sempre a raiz**, nunca o elo clicado. Sem isso a cadeia
      # viraria uma lista ligada e a tela de renovações mostraria só o vizinho.
      def raiz_de(operation)
        operation.original_id.presence || operation.id
      end

      # Os 13 campos de `:119-138`.
      #
      # ### `original_due_date`: o `design.md` leu a fonte errado, e a fonte vence
      #
      # O `design.md` desta fatia diz, no golden `M3`, que o `original_due_date`
      # da nova operação é **30/06/2026**, "o vencimento da que foi renovada".
      # **Não é o que o código de 2022 faz.** `create_renovation` passa
      # `original_due_date: original.due_date` (`risk_operation.rb:134`), mas o
      # `before_validation on: [:create]` do próprio model roda **depois** da
      # atribuição e faz `self.original_due_date = self.due_date` (`:23`) — ou
      # seja, sobrescreve com o vencimento **NOVO** (18/09/2026 no golden).
      #
      # Pela **DEC-103b** ("espelhar o código de 2022 como está, sem corrigir o
      # que parecer errado") o comportamento replicado é o do callback. A linha
      # abaixo fica escrita, e não removida, porque é o que a fonte faz: assim o
      # espelho é literal e a sobrescrita é visível a quem ler.
      #
      # Consequência prática: `original_due_date` da renovação **não** aponta
      # para o elo anterior. Quem quiser a data do elo anterior lê a operação de
      # `original_id`. Está no relatório da fatia e no `improvements-log.md`.
      def campos_copiados(original)
        {
          original_due_date: original.due_date,
          title: original.title,
          operation_type_id: original.operation_type_id,
          operation_subtype_id: original.operation_subtype_id,
          project_id: original.project_id,
          company_id: original.company_id,
          carrier_id: original.carrier_id,
          risk_control_id: original.risk_control_id,
          contract_number: original.contract_number,
          operation_value: original.operation_value,
          agreed_rate: original.agreed_rate,
          observation: original.observation,
          is_on_variable: original.is_on_variable,
          receivable_id: original.receivable_id,
          original_balance: original.original_balance
        }
      end

      def not_found
        { status: 404, error: 'Operação de risco não encontrada.' }
      end

      def sem_janela
        { status: 422, error: 'O par estático do limite não tem janela de datas e não é renovável.' }
      end

      def unprocessable(record)
        return { status: 422, error: 'Não foi possível renovar a operação.' } if record.nil?

        { status: 422, error: record.errors.full_messages.to_sentence, details: record.errors.messages }
      end
    end
  end
end

# frozen_string_literal: true

module Receivables
  # S6 — **a metade compartilhada da gravação do borderô**. Não é um endpoint:
  # é o que `CreateService` e `UpdateService` têm em comum, escrito uma vez.
  #
  # ## A sequência, e por que ela é esta
  #
  # No legado o controller (`../sfg/app/controllers/pub/receivables_controller.rb:77,89`)
  # fazia **dois `save`**:
  #
  # 1. `@receivable.save` — dispara o `before_validation` que calcula tudo
  #    **sem nenhuma tarifa** (elas ainda não existem) e o `after_commit` que
  #    cria a `RiskOperation` com esse líquido errado;
  # 2. grava as tarifas, e `@receivable.save` de novo — recalcula os
  #    `tarifas_*`, mas o `after_commit` agora cai no ramo de `:168`, que só
  #    atualiza tipo e subtipo. **O valor errado da operação fica congelado.**
  #
  # É o **D-11**, e ele está em produção: por isso o **DEC-36** mandou o ETL
  # **copiar** `operation_value` como está, em vez de recalcular.
  #
  # Aqui a ordem é outra, e o borderô novo nasce certo:
  #
  #     transação
  #       1. monta as tarifas (em memória, ainda não gravadas)
  #       2. valida as entradas  → InputGuard, 422 antes de qualquer conta
  #       3. calcula UMA vez     → Receivables::Calculator, com as tarifas
  #       4. grava borderô + tarifas
  #       5. sincroniza o risco  → chamada EXPLÍCITA, com o líquido definitivo
  #     fim
  #
  # **Passo 5 é chamada, não `after_commit`.** Um callback não sabe se está
  # dentro de uma transação de lote, não pode ser desligado no recálculo em
  # massa (OPS-151) e roda depois do commit — quando já não dá para desfazer.
  class WriteService
    class << self
      include ApiResponseHandler

      private

      # O núcleo, compartilhado por criação e edição.
      #
      # `taxes_payload` `nil` significa "não mexa nas tarifas" (o payload de
      # edição sem a chave preserva as existentes, tarefa 2.23). Um array —
      # inclusive vazio — significa "a lista passa a ser esta", que é o que
      # implementa a **DEC-72**: remover tarifa fica **pendente no formulário**
      # e só acontece no Salvar, dentro desta transação.
      def persist(entry:, attrs:, taxes_payload:, actor:, project:)
        entry.project = project
        entry.user_id ||= actor&.id
        assign_writable(entry, attrs)

        taxes = TaxService.build(entry: entry, payload: taxes_payload)
        return unprocessable(entry) if entry.errors.any?

        erros = InputGuard.check(entry.calculator_input(taxes: taxes))
        return guard_error(erros) if erros.any?

        resultado = Calculator.call(
          entry.calculator_input(taxes: taxes),
          iof_rate: IofRate.effective_on(entry.date || Date.current)
        )
        erros = InputGuard.result_errors(resultado)
        return guard_error(erros) if erros.any?

        entry.assign_attributes(resultado)

        begin
          ActiveRecord::Base.transaction do
            raise ActiveRecord::Rollback unless save_entry(entry)

            TaxService.persist!(entry: entry, taxes: taxes, payload: taxes_payload)
            RiskSyncService.call!(entry)
          end
        rescue ActiveRecord::RecordInvalid => e
          # **Sem este resgate a resposta é 500, não 422.**
          #
          # `RiskSyncService` levanta de propósito — é o que desfaz a transação
          # quando a operação estática do pré-faturamento não existe, ou quando
          # o limite some entre a validação e a gravação. Mas `RecordInvalid`
          # subindo até o endpoint cai no `rescue_from StandardError` local (que
          # existe para não vazar backtrace, F-3) e vira **"o servidor
          # quebrou"** — quando o que houve foi uma regra de negócio recusando,
          # com a frase pronta em `entry.errors`.
          #
          # `TaxService.persist!` usa `save!` pelo mesmo motivo, e cai aqui pelo
          # mesmo caminho.
          registro = e.record
          if registro && registro != entry && registro.errors.any?
            entry.errors.add(:base, registro.errors.full_messages.to_sentence)
          end
          entry.errors.add(:base, e.message) if entry.errors.empty?
          return unprocessable(entry)
        end

        return unprocessable(entry) if entry.errors.any? || entry.new_record?

        entry.reload
      end

      def assign_writable(entry, attrs)
        WRITABLE_ATTRIBUTES.each do |attribute|
          next unless attrs.key?(attribute)

          entry.public_send(:"#{attribute}=", attrs[attribute])
        end
      end

      # `project_id`, `user_id` e `id` **nunca** entram: os três vêm do
      # servidor. `user_id` no corpo é ignorado — o autor é o da sessão
      # (tarefa 2.22).
      WRITABLE_ATTRIBUTES = (
        ReceivableEntry::INPUT_COLUMNS + %i[
          date data_credito nro_bordero contrato description observacoes
          company_id carrier_id wallet_id receivable_kind_id resource_source_id
          risk_operation_subtype_id nominal_tax
        ]
      ).freeze

      def save_entry(entry)
        entry.save
      rescue ActiveRecord::RecordNotUnique => e
        Rails.logger.info("[#{name}] índice único recusou: #{e.message}")
        entry.errors.add(:base, 'Já existe um borderô com estes dados neste projeto.')
        false
      end

      def guard_error(erros)
        { status: 422, error: erros.to_sentence, details: { base: erros } }
      end

      def unprocessable(record)
        { status: 422, error: record.errors.full_messages.to_sentence, details: record.errors.messages }
      end

      def not_found
        { status: 404, error: 'Borderô não encontrado.' }
      end

      # C1 aplicado às referências do CORPO: empresa, portador e catálogos
      # precisam existir, e a empresa precisa ser **do projeto corrente**.
      # Sem isto, um `company_id` de outro projeto entraria pela porta dos
      # fundos e o borderô nasceria apontando para fora do tenant.
      def validate_references(project, attrs)
        erros = []
        if attrs.key?(:company_id)
          erros << 'Empresa não encontrada neste projeto.' unless
            Company.for_project(project).exists?(id: attrs[:company_id])
        end
        if attrs.key?(:carrier_id)
          # **Um critério só** para portador oferecível — o mesmo que a tela
          # usa. Ter dois critérios foi o que fez a tela do legado oferecer
          # portador que o servidor recusava.
          conectados = ProjectToCarrierConnection.for_project(project).select(:carrier_id)
          erros << 'Portador não conectado a este projeto.' unless
            Carrier.where(id: conectados).exists?(id: attrs[:carrier_id])
        end
        if attrs[:risk_operation_subtype_id].present? &&
           !RiskOperationSubtype.exists?(id: attrs[:risk_operation_subtype_id])
          erros << 'Subtipo de operação de risco não encontrado.'
        end
        erros
      end

      def uuid?(value)
        value.to_s.match?(ProjectScopedService::UUID_FORMAT)
      end
    end
  end
end

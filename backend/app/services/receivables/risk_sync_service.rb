# frozen_string_literal: true

module Receivables
  # S6 / **BE-183** — a sincronia entre o borderô e a exposição ao risco.
  #
  # ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
  #
  # Todo este comportamento depende de `receivable_entries.risk_operation_subtype_id`,
  # coluna criada por `20220610122917_add_risk_operation_type_to_receivable_entries`
  # — uma das **24 migrations que nunca subiram**. Conferido no dump: o `COPY`
  # de `receivable_entries` tem 68 colunas e **nenhuma das duas** está lá.
  #
  # Ou seja: em três anos de produção, **nenhum borderô jamais gerou operação de
  # risco**. O `after_commit` de `../sfg/app/models/receivable_entry.rb:124-176`
  # é código de 2022 que nunca rodou. Por DEC-103b ele vem espelhado como está,
  # e o golden desta família carrega a marca — o teste trava a **leitura do
  # código**, não um comportamento observado.
  #
  # ## Chamada explícita, não `after_commit`
  #
  # O legado usava `after_commit`, e o próprio autor escreveu ali:
  # *"# aqui está o caso de bugar o save do recebível"*. Três problemas
  # concretos disso:
  #
  # - roda **depois** do commit: se a criação da operação falhar, o borderô já
  #   está gravado e a exposição fica faltando, sem ninguém saber;
  # - dispara **em todo save**, então os dois `save` do controller o chamavam
  #   duas vezes (D-11);
  # - não pode ser desligado no recálculo em massa (OPS-151), que
  #   reprocessaria a base inteira criando movimento duplicado.
  #
  # Aqui é uma chamada de uma linha, **dentro da transação**, com o líquido já
  # definitivo. Roda **uma vez** por operação de escrita.
  #
  # ## Onde o ai9 é mais rígido, e por quê
  #
  # `risk_operations.risk_control_id` é **NOT NULL** na S5 — *"operação sem
  # limite é exposição sem teto"*. O legado criava a operação sem apontar para
  # limite nenhum. Aqui o limite é o mesmo que a validação `BE-181` já exigiu
  # ativo, então não há caminho em que ele falte; se faltar, **falha com erro**
  # em vez de gravar exposição órfã.
  class RiskSyncService
    class << self
      # Levanta em caso de inconsistência: quem chama está dentro da transação
      # de gravação, e desfazer é a resposta certa.
      def call!(entry)
        return if entry.risk_operation_subtype_id.blank?

        subtype = entry.risk_operation_subtype
        return if subtype.nil?

        # A associação em `RiskOperationSubtype` chama-se `operation_type` (a COLUNA
        # é `risk_operation_type_id`). Usar o nome da coluna como se fosse
        # associação levanta `NoMethodError` e o endpoint devolve 500 — foi
        # exatamente o que apareceu rodando o teste de BE-181.
        if subtype.operation_type&.has_pre_faturamento?
          release_on_static_operation!(entry, subtype)
        else
          upsert_operation!(entry, subtype)
        end
      end

      private

      # `receivable_entry.rb:128-146` — tipo COM pré-faturamento: o borderô não
      # abre operação nova, ele **libera recurso** na operação estática do par
      # (B-08 da S5).
      #
      # **Uma divergência deliberada:** o legado fazia `unless static_op.nil?`
      # e seguia em silêncio quando não achava a operação estática — o borderô
      # era gravado e a liberação simplesmente não acontecia. Aqui falta de
      # operação estática **levanta**. A tarefa 2.25 pede exatamente isso
      # ("operação estática ausente falha com erro em vez de silêncio"), e o
      # critério é o do DEC-30 exceção 1: silêncio aqui produz exposição errada
      # num banco novo, não preserva um número existente.
      def release_on_static_operation!(entry, subtype)
        static_op = RiskOperation.where(
          project_id: entry.project_id, company_id: entry.company_id,
          carrier_id: entry.carrier_id, operation_type_id: entry.risk_operation_type_id,
          operation_subtype_id: subtype.id, is_static: true
        ).first

        if static_op.nil?
          raise ActiveRecord::RecordInvalid.new(entry).tap {
            entry.errors.add(:risk_operation_subtype_id,
                             'não tem operação estática de pré-faturamento para este limite. ' \
                             'O borderô não pode liberar recurso sem ela.')
          }
        end

        RiskMovement.create!(
          user_id: entry.user_id,
          date: entry.date,
          movement_type_id: RiskMovementType.release.id,
          movement_value: entry.valor_liquido,
          balance: 0,
          project_id: entry.project_id,
          company_id: entry.company_id,
          carrier_id: entry.carrier_id,
          risk_operation_id: static_op.id,
          observation: 'Gerado automaticamente a partir de recebível'
        )
      end

      # `receivable_entry.rb:148-172` — tipo liquidável: cria a operação na
      # primeira vez, e nas seguintes **só atualiza tipo e subtipo**.
      #
      # Manter o `update` restrito a tipo/subtipo é o que produz o D-11 no
      # legado (o valor nunca é revisto). Aqui não há defeito a herdar porque a
      # criação já acontece **depois** das tarifas — mas o `update` continua
      # atualizando o valor, que é o que o DEC-36 registra como a diferença
      # entre borderô histórico e borderô novo.
      def upsert_operation!(entry, subtype)
        control = RiskControl.find_by(
          project_id: entry.project_id, company_id: entry.company_id,
          carrier_id: entry.carrier_id, risk_operation_type_id: entry.risk_operation_type_id,
          is_active: true
        )
        if control.nil?
          raise ActiveRecord::RecordInvalid.new(entry).tap {
            entry.errors.add(:risk_operation_subtype_id, 'não tem limite de risco ativo para esta combinação.')
          }
        end

        operacao = entry.risk_operation
        if operacao.nil?
          RiskOperation.create!(
            user_id: entry.user_id,
            issue_date: entry.date,
            due_date: entry.data_credito || entry.date,
            title: "Operação do recebível ##{entry.nro_bordero.presence || entry.id}",
            operation_type_id: entry.risk_operation_type_id,
            operation_subtype_id: subtype.id,
            project_id: entry.project_id,
            company_id: entry.company_id,
            carrier_id: entry.carrier_id,
            risk_control_id: control.id,
            contract_number: entry.nro_bordero,
            operation_value: entry.valor_liquido,
            agreed_rate: entry.nominal_tax || 0,
            observation: 'Gerado automaticamente a partir de recebível',
            receivable_id: entry.id
          )
        else
          operacao.update!(
            operation_type_id: entry.risk_operation_type_id,
            operation_subtype_id: subtype.id,
            operation_value: entry.valor_liquido
          )
        end
      end
    end
  end
end

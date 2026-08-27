# frozen_string_literal: true

module Risk
  # S7 / **BE-270..BE-273** — o **extrato** da operação: listar, lançar, editar
  # e excluir movimento.
  #
  # ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
  #
  # `create_risk_movements` e `create_risk_movement_types` estão entre as **24
  # migrations que nunca subiram** (`analise-dump-producao.md` §1). Nenhum
  # movimento de risco existiu em produção. A fonte é
  # `../sfg/app/controllers/pub/risk_movements_controller.rb` e
  # `../sfg/app/models/risk_movement.rb`; o golden trava a leitura dela.
  #
  # ## A IDOR que morre aqui — BE-270
  #
  # `risk_movements#search` (`:14-21`) é
  # `RiskMovement.where(risk_operation_id: params[:risk_operation_id])`. **Não há
  # escopo de projeto nenhum**: qualquer autenticado que tenha (ou adivinhe) o
  # id de uma operação lê o extrato dela, de qualquer projeto. É a segunda das
  # duas IDORs da família D-01/D-16/D-29/D-76/D-100 nesta fatia, e é
  # **EXCEÇÃO-2 do DEC-30** — segurança não se replica.
  #
  # Aqui a operação é resolvida por `Risk::OperationService.find(project, id)`
  # antes de qualquer consulta a movimento: id de outro projeto responde **404**,
  # igual a id inexistente.
  #
  # ## A paginação que existia e não funcionava
  #
  # `fetch_loq` (`:94-102`) lê `l`, `o` e `q`, aplica default 20 — e **nunca os
  # usa**: a `search` devolve a lista inteira. Aqui a relação é paginada pelo
  # endpoint (Kaminari, DEC-62) e o total é real.
  class MovementService
    class << self
      include ApiResponseHandler

      # ------------------------------------------------------------------
      # BE-270 — listagem, por `sequence` asc
      # ------------------------------------------------------------------
      # `:17` ordena por `order` (que aqui é `sequence`), e não por data: é a
      # ordem que o recálculo acabou de reatribuir, logo é a ordem em que os
      # saldos foram acumulados. Ordenar por data daria o mesmo resultado depois
      # de um recálculo e divergiria antes dele.
      def index(project:, operation_id:)
        operation = Risk::OperationService.find(project, operation_id)
        return not_found_operation if operation.nil?

        escopo = RiskMovement.where(risk_operation_id: operation.id)
                             .includes(:movement_type, :author)
                             .order(sequence: :asc, created_at: :asc)

        { status: 200, data: escopo, operation: operation }
      end

      # ------------------------------------------------------------------
      # BE-271 — os helpers de "novo movimento" e "transferência"
      # ------------------------------------------------------------------
      # `new` (`:23-32`) e `transfer` (`:34-44`) faziam
      # `RiskOperation.where(id: …).first` e logo `@risk_operation.id` —
      # **`NoMethodError` em `nil`** para id inexistente, ou seja 500. Aqui é
      # 404, e o payload já traz o que o drawer precisa: os tipos manuais e,
      # na transferência, o tipo fixado.
      def form_options(project:, operation_id:, mode: 'new')
        operation = Risk::OperationService.find(project, operation_id)
        return not_found_operation if operation.nil?

        if mode.to_s == 'transfer'
          return { status: 422, error: Risk::TransferService::NOT_PRE } unless operation.is_pre?

          tipo = RiskMovementType.transfer_out
          return { status: 200,
                   data: { mode: 'transfer', movement_type_id: tipo.id, movement_type_locked: true,
                           movement_types: [tipo], operation: operation } }
        end

        { status: 200,
          data: { mode: 'new', movement_type_id: nil, movement_type_locked: false,
                  movement_types: RiskMovementType.manual.order(title: :asc).to_a,
                  operation: operation } }
      end

      # ------------------------------------------------------------------
      # BE-272 — lançamento
      # ------------------------------------------------------------------
      # Três regras, e as três estão no `tasks.md` 4.3:
      #
      # 1. **`user_id` vem de `current_user`** (`:50`), nunca do payload — o
      #    legado permitia `user_id` no `permit` (`:121`);
      # 2. **`company_id`/`carrier_id`/`project_id` são copiados da operação** e
      #    o que vier no payload é descartado (`risk_movement.rb:15-19`). É
      #    replicação: é o que mantém o dado histórico coerente quando a empresa
      #    muda de nome ou o portador é reconectado;
      # 3. **`movement_value > 0` passa a valer no servidor** (decisão **B-05**).
      #    No legado só o botão "Salvar" do drawer conferia; por requisição
      #    direta entrava movimento de valor zero ou negativo, e valor negativo
      #    **inverte o sinal do movimento** — um crédito de −1.000 vira débito.
      #    É registro corrompido, não convenção de sinal, e por isso não cai no
      #    DEC-01.
      #
      # O tipo tem de ser **manual** (`is_transfer = false AND is_active = true`):
      # a transferência entra por `Risk::TransferService`, que grava o par.
      def create(project:, operation_id:, attrs:, actor: nil)
        operation = Risk::OperationService.find(project, operation_id)
        return not_found_operation if operation.nil?

        tipo = RiskMovementType.find_by(id: attrs[:movement_type_id])
        return tipo_invalido if tipo.nil?
        return { status: 422, error: 'Valor do movimento deve ser maior que zero.' } unless positivo?(attrs[:movement_value])

        return Risk::TransferService.call(operation: operation, attrs: attrs, actor: actor) if tipo.is_transfer?
        return tipo_nao_manual unless RiskMovementType.manual.exists?(id: tipo.id)

        movimento = build(operation, attrs, actor)
        return unprocessable(movimento) unless save_safely(movimento)

        { status: 201, data: movimento.reload }
      end

      # ------------------------------------------------------------------
      # BE-273 — edição
      # ------------------------------------------------------------------
      # O tipo de um movimento de **transferência** é readonly: trocá-lo
      # deixaria o par com tipos incoerentes (o espelho continuaria "Transferência
      # Recebida"). O legado permitia, e a tela escondia o campo.
      def update(project:, operation_id:, id:, attrs:, actor: nil)
        movimento = find(project, operation_id, id)
        return not_found_movement if movimento.nil?
        return { status: 422, error: 'Valor do movimento deve ser maior que zero.' } unless positivo?(attrs[:movement_value])

        permitidos = attrs.slice(:date, :movement_value, :observation)
        if attrs.key?(:movement_type_id) && !movimento.movement_type&.is_transfer?
          tipo = RiskMovementType.find_by(id: attrs[:movement_type_id])
          return tipo_invalido if tipo.nil?
          return tipo_nao_manual unless RiskMovementType.manual.exists?(id: tipo.id)

          permitidos[:movement_type_id] = tipo.id
        end

        movimento.assign_attributes(permitidos)
        movimento.user_id = actor&.id if movimento.user_id.blank?

        return unprocessable(movimento) unless save_safely(movimento)

        { status: 200, data: movimento.reload }
      end

      # ------------------------------------------------------------------
      # BE-273 — exclusão
      # ------------------------------------------------------------------
      # `after_destroy` do model salva a operação, o que refaz a cadeia e
      # **renumera o `sequence` dos restantes**.
      #
      # **O movimento automático de "Liberação do Recurso" PODE ser excluído e
      # NÃO é recriado** — o `after_create` que o cria só roda no create da
      # operação. A cadeia passa a partir de `original_balance`. É o legado, e
      # está replicado de propósito: é assim que o operador corrige um capital
      # liberado em duas parcelas.
      #
      # Movimento de transferência leva o par junto: sem isso a contrapartida
      # ficaria pendurada numa transferência que não existe mais.
      def destroy(project:, operation_id:, id:)
        movimento = find(project, operation_id, id)
        return not_found_movement if movimento.nil?

        par = movimento.pair_movement
        RiskMovement.transaction do
          movimento.destroy!
          par&.destroy!
        end

        { status: 200, data: { deleted: true, id: id.to_s } }
      end

      # Escopo C1: a operação é resolvida no projeto ANTES de o movimento ser
      # procurado. Um `risk_movement_id` de outro projeto não é encontrado.
      def find(project, operation_id, id)
        operation = Risk::OperationService.find(project, operation_id)
        return nil if operation.nil?
        return nil unless Risk::OperationService.uuid?(id)

        RiskMovement.where(risk_operation_id: operation.id).find_by(id: id)
      end

      private

      def build(operation, attrs, actor)
        RiskMovement.new(
          risk_operation_id: operation.id,
          movement_type_id: attrs[:movement_type_id],
          date: attrs[:date],
          movement_value: attrs[:movement_value],
          observation: attrs[:observation],
          balance: 0,
          user_id: actor&.id
        )
      end

      def positivo?(valor)
        return true if valor.nil? # ausente = "não estou mexendo neste campo"

        BigDecimal(valor.to_s) > 0
      rescue ArgumentError, TypeError
        false
      end

      def save_safely(record)
        record.save
      end

      def not_found_operation
        { status: 404, error: 'Operação de risco não encontrada.' }
      end

      def not_found_movement
        { status: 404, error: 'Movimento não encontrado.' }
      end

      def tipo_invalido
        { status: 422, error: 'Tipo de movimentação não encontrado.' }
      end

      def tipo_nao_manual
        { status: 422,
          error: 'Tipo de movimentação não disponível para lançamento manual ' \
                 '(está inativo ou é exclusivo do sistema).' }
      end

      def unprocessable(record)
        { status: 422, error: record.errors.full_messages.to_sentence, details: record.errors.messages }
      end
    end
  end
end

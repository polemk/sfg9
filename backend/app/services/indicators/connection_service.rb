# frozen_string_literal: true

module Indicators
  # S10 / BE-707, BE-709, BE-710, BE-711 — **conexões e indicadores específicos**.
  #
  # É a tela "Indicadores específicos" do grupo Projeto: a lista de tudo que
  # pode aparecer na grade mensal deste projeto (os **globais** mais os
  # **específicos dele**), com um interruptor por linha.
  #
  # ## As quatro coisas que esta classe corrige, todas medidas na fonte
  #
  # **1. `constantize` de input do usuário (`BE-707`) — risco de execução de
  # código.** `project_indicator_connections_controller.rb:24,26,47,49,68,70`
  # faz `params[:owner_type].constantize` e `params[:connection_type].constantize`:
  # qualquer classe Ruby carregada podia ser instanciada por parâmetro de URL.
  # Aqui não há tipo dinâmico nenhum — o recurso é `Indicator`, escrito no
  # código.
  #
  # **2. A busca da tela não filtra nada.** Os ramos
  # `if params[:connection_type] == "Carrier" / "Project"` (`:31,34`) **nunca
  # casam** com `"Indicator"`, então `q`, `limit` e `offset` são simplesmente
  # ignorados — e o front chama com `l=200`. Aqui `q`, ordenação e paginação
  # valem.
  #
  # **3. O erro de conectar vários não é agregado (`BE-709`).** O laço de
  # `update_connections` (`:81-86`) reatribui `@connection` a cada volta e **nem
  # verifica o `save`**; só a última conexão é inspecionada depois. Conectar 3
  # indicadores com 1 falha **pode reportar sucesso**. Aqui há transação e
  # relatório item a item.
  #
  # **4. O ramo `destroy` explode ou apaga o indicador errado (`BE-711`).**
  # Quando o indicador é global, `@connection` vem do `before_action` e é uma
  # **`Relation`**, não um record — `.errors` levanta `NoMethodError`. O próprio
  # `FIXME` do arquivo (`:92-93`) registra que a issue #7102 corrigia um id
  # errado que **deletava o indicador incorreto**.
  #
  # ## O que é replicado
  #
  # **Desconectar NÃO apaga lançamento** (Q-R31). O indicador some da grade e o
  # histórico continua no banco; reconectar o traz de volta inteiro. É
  # conservador e não perde dado — replicado de propósito.
  class ConnectionService
    class << self
      include ApiResponseHandler

      # Os indicadores que este projeto pode ver: **globais + específicos dele**.
      # É o `@connection_type.where(project_id: [@owner.id, nil])` do legado
      # (`:30`), com a busca e a paginação passando a valer.
      #
      # Devolve a RELAÇÃO — o endpoint pagina.
      def connectable(project:, params: {})
        scope = Indicator.kept.available_for(project)
        scope = scope.search(params[:q]) if params[:q].present?
        scope = scope.active if truthy?(params[:active])
        Indicator::ORDERING.apply(scope, keys: params[:ordering_keys], styles: params[:ordering_style])
      end

      # Ids dos indicadores já conectados a este projeto — uma consulta para a
      # página inteira, em vez de uma por linha.
      def connected_ids(project)
        Set.new(ProjectIndicatorConnection.for_project(project).pluck(:indicator_id))
      end

      # `BE-709` — conecta N indicadores, **com relatório por item**.
      #
      # Tudo ou nada: se um item falha, a transação volta atrás e a resposta diz
      # **qual** falhou e por quê. O legado gravava os que davam certo e
      # reportava o estado do último.
      def connect(project:, indicator_ids:, actor: nil)
        aplicar(project: project, indicator_ids: indicator_ids, actor: actor, acao: :connect)
      end

      # `BE-710` — desconecta. Par inexistente é **no-op idempotente**, não
      # `nil.destroy` → 500: desconectar duas vezes tem de dar o mesmo resultado.
      # **Os `indicator_entries` não são tocados** (Q-R31).
      def disconnect(project:, indicator_ids:, actor: nil)
        aplicar(project: project, indicator_ids: indicator_ids, actor: actor, acao: :disconnect)
      end

      # `BE-711` — exclui um indicador **específico** deste projeto: a conexão
      # sai primeiro (o `restrict_with_error` do model depende disso) e o
      # indicador vai para a exclusão LÓGICA de `IndicatorService#destroy`.
      #
      # Indicador **global** é recusado com 422 e a frase do legado — no legado
      # esse mesmo ramo levantava `NoMethodError` antes de conseguir dizê-la.
      def destroy_specific(project:, indicator_id:, actor: nil)
        indicator = Indicator.kept.available_for(project).find_by(id: indicator_id) if uuid?(indicator_id)
        return not_found if indicator.nil?

        if indicator.global?
          return { status: 422,
                   error: 'Não é possível remover indicadores globais com associação. ' \
                          'Desconecte-o do projeto ou exclua-o no catálogo.' }
        end

        resultado = nil
        Indicator.transaction do
          ProjectIndicatorConnection.where(project_id: project.id, indicator_id: indicator.id).destroy_all
          resultado = IndicatorService.destroy(id: indicator.id, actor: actor)
          raise ActiveRecord::Rollback unless resultado[:status] == 200
        end

        resultado
      end

      private

      def aplicar(project:, indicator_ids:, actor:, acao:)
        ids = Array(indicator_ids).map(&:to_s).uniq.select { |i| uuid?(i) }
        return { status: 422, error: 'Informe ao menos um indicador.' } if ids.empty?

        # **Só indicadores que este projeto alcança.** Id de indicador
        # específico de OUTRO projeto simplesmente não é encontrado — nunca 403,
        # que confirmaria a existência do registro alheio.
        alcancaveis = Indicator.kept.available_for(project).where(id: ids).index_by { |i| i.id.to_s }
        relatorio = []

        Indicator.transaction do
          ids.each do |id|
            indicator = alcancaveis[id]
            if indicator.nil?
              relatorio << { indicator_id: id, ok: false, error: 'Indicador não encontrado neste projeto.' }
              next
            end

            relatorio << (acao == :connect ? conectar(project, indicator) : desconectar(project, indicator))
          end

          raise ActiveRecord::Rollback if relatorio.any? { |r| !r[:ok] }
        end

        falhas = relatorio.reject { |r| r[:ok] }
        if falhas.any?
          return { status: 422,
                   error: falhas.map { |f| f[:error] }.uniq.to_sentence,
                   details: { items: relatorio } }
        end

        Rails.logger.info("[Indicators] #{actor&.id} #{acao} #{ids.size} indicador(es) no projeto #{project.id}")
        { status: 200, data: { items: relatorio, connected_ids: connected_ids(project).to_a } }
      end

      def conectar(project, indicator)
        conexao = ProjectIndicatorConnection.find_or_initialize_by(project_id: project.id, indicator_id: indicator.id)
        # Já conectado é sucesso, não erro: o interruptor da tela é um estado
        # desejado, não um comando incremental.
        return item_ok(indicator, 'connected') if conexao.persisted?

        if conexao.save
          item_ok(indicator, 'connected')
        else
          { indicator_id: indicator.id, title: indicator.title, ok: false,
            error: "#{indicator.title}: #{conexao.errors.full_messages.to_sentence}" }
        end
      rescue ActiveRecord::RecordNotUnique
        # Corrida entre duas abas: o índice único do banco venceu, e o estado
        # desejado é justamente esse.
        item_ok(indicator, 'connected')
      end

      def desconectar(project, indicator)
        conexao = ProjectIndicatorConnection.find_by(project_id: project.id, indicator_id: indicator.id)
        # Idempotente: não conectado já está no estado pedido.
        return item_ok(indicator, 'disconnected') if conexao.nil?

        conexao.destroy
        item_ok(indicator, 'disconnected')
      end

      def item_ok(indicator, estado)
        { indicator_id: indicator.id, title: indicator.title, ok: true, state: estado }
      end

      def uuid?(value)
        value.to_s.match?(ProjectScopedService::UUID_FORMAT)
      end

      def not_found
        { status: 404, error: 'Indicador não encontrado.' }
      end

      def truthy?(value)
        ActiveModel::Type::Boolean.new.cast(value) == true
      end
    end
  end
end

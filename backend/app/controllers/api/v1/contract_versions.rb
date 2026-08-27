# frozen_string_literal: true

module Api
  module V1
    # S12 / BE-335, BE-336, BE-338, OPS-333 — **publicar e administrar versões
    # de contrato**.
    #
    # ## O gate que nunca existiu (DEC-38, achado A-1)
    #
    # `contracts_controller.rb` do legado tem 101 linhas e **zero**
    # `before_action`, `may?`, `admin?`, `og?` ou `authorize`. As rotas
    # (`routes.rb:30-31`) não têm constraint. O `create` (`:56-67`) instancia,
    # carimba `creator = current_user` e salva. **Hoje qualquer usuário
    # autenticado publica um novo Termos de Uso** — e como o vigente é o de
    # maior versão, o texto que todo mundo aceita passa a ser o dele.
    #
    # A DEC-38 cria o recurso `contract_versions`: **CRUD para OG e Admin**, `-`
    # para Gerente e Colaborador. `contracts` (ler e aceitar) fica exatamente
    # como a matriz aprovou. O gate é o `authorize!` da matriz, no servidor —
    # não a ausência de botão.
    #
    # ## O mass assignment que vai junto
    #
    # O `permit` do legado aceitava **`:id` e `:version`**
    # (`contracts_controller.rb:87-93`). Com `:version` no payload, publicar a
    # versão 999 era um campo de formulário; com `:id`, `create` podia
    # sobrescrever outra linha. Aqui nem um nem outro são declarados no Grape —
    # e o que o Grape não declara não chega ao `params` do endpoint.
    class ContractVersions < Grape::API
      helpers Api::V1::ControllerHelpers

      helpers do
        def find_version!
          contrato = ::Contract.find_by(id: params[:id])
          error!({ error: 'not_found', message: 'Versão de contrato não encontrada.' }, 404) if contrato.nil?
          contrato
        end
      end

      namespace :contract_versions do
        before { authenticate_user! }

        desc 'Histórico completo de versões' do
          detail 'Da mais recente para a mais antiga. Busca por título e por tipo.'
        end
        params do
          optional :kind, type: String, desc: 'Tipo ou slug'
          optional :q, type: String, desc: 'Busca por título'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!('contract_versions', :read)

          escopo = ::Contract.all.order(kind: :asc, version: :desc)
          if params[:kind].present?
            kind = ::Contract.kind_for(params[:kind])
            # Tipo fora do catálogo devolve lista vazia, não a base inteira. No
            # legado o filtro era a lista fixa `@availabe_kinds` (o typo é do
            # original) e tipo inesperado ficava **invisível e inéditável**.
            escopo = kind.present? ? escopo.where(kind: kind) : escopo.none
          end
          if params[:q].present?
            escopo = escopo.where(
              ActiveRecord::Base.sanitize_sql_array(
                ['unaccent(title) ILIKE unaccent(?)', "%#{params[:q]}%"]
              )
            )
          end

          Api::Entities::Contract.represent(paginate(escopo), admin: true)
        end

        desc 'Tipos do catálogo e o estado de cada um'
        get 'catalog' do
          authorize!('contract_versions', :read)

          ::Contract::KINDS.map do |kind|
            vigente = ::Contracts::Resolver.current(kind)
            {
              kind: kind,
              slug: ::Contract::SLUGS.fetch(kind),
              current_version: vigente&.version,
              versions_count: ::Contract.of_kind(kind).count,
              accepted_count: vigente ? vigente.contract_deals.count : 0
            }
          end
        end

        desc 'Rascunho da próxima versão' do
          detail 'Pré-preenche com título e texto da anterior. O PRIMEIRO contrato de um tipo abre VAZIO — ' \
                 'no legado esse caso estourava NoMethodError (`where(kind:).last.version + 1`).'
        end
        params do
          requires :kind, type: String
        end
        get 'prefill' do
          authorize!('contract_versions', :create)

          dados = ::Contracts::PrefillService.call(params[:kind])
          error!({ error: 'not_found', message: 'Tipo de contrato desconhecido.' }, 404) if dados.nil?
          dados
        end

        desc 'Uma versão, com o texto'
        params { requires :id, type: String }
        get ':id' do
          authorize!('contract_versions', :read)
          Api::Entities::Contract.represent(find_version!, type: :full, admin: true)
        end

        desc 'Quantos aceites ficariam com hash divergente se o texto mudasse' do
          detail 'Mitigação 2 da DEC-80 — o aviso chega a quem pode decidir, porque só OG e Admin publicam.'
        end
        params { requires :id, type: String }
        get ':id/impact' do
          authorize!('contract_versions', :read)
          contrato = find_version!
          {
            accepted_count: contrato.contract_deals.count,
            divergent_count: contrato.divergent_deals_count,
            is_current: ::Contracts::Resolver.current(contrato.kind)&.id == contrato.id
          }
        end

        desc 'Exporta a prova de aceite (CSV)' do
          detail 'OPS-333 / DEC-80: usuário, versão, data/hora, IP, user-agent, hash e o TEXTO INTEGRAL aceito.'
        end
        params { requires :id, type: String }
        get ':id/proof' do
          authorize!('contract_versions', :read)
          contrato = find_version!

          content_type 'text/csv; charset=utf-8'
          header 'Content-Disposition',
                 "attachment; filename=\"prova-aceite-#{contrato.slug_value}-v#{contrato.version}.csv\""
          env['api.format'] = :txt
          ::Contracts::ProofExport.to_csv(contrato.contract_deals)
        end

        desc 'Publica uma nova versão' do
          detail 'DEC-38: OG e Admin. O autor é o da sessão; `id` e `version` NÃO são aceitos do payload.'
        end
        params do
          requires :kind, type: String, desc: 'Tipo do catálogo (ou slug)'
          requires :title, type: String
          requires :description, type: String, desc: 'HTML do corpo'
        end
        post '' do
          authorize!('contract_versions', :create)

          kind = ::Contract.kind_for(params[:kind])
          if kind.blank?
            error!({ error: 'unknown_kind', message: 'Tipo de contrato fora do catálogo.' }, 422)
          end

          contrato = ::Contract.new(kind: kind, title: params[:title], creator: acting_user)
          contrato.description = params[:description]

          begin
            contrato.save!
          rescue ActiveRecord::RecordInvalid => e
            error!({ error: 'invalid', message: e.record.errors.full_messages.to_sentence,
                     details: e.record.errors.messages }, 422)
          rescue ActiveRecord::RecordNotUnique
            # A garantia do banco contra publicações concorrentes. Duas
            # requisições simultâneas não recebem o mesmo número: uma perde e
            # tenta de novo, com o próximo.
            contrato.version = nil
            retry_contrato = ::Contract.new(kind: kind, title: params[:title], creator: acting_user)
            retry_contrato.description = params[:description]
            retry_contrato.save!
            contrato = retry_contrato
          end

          status 201
          Api::Entities::Contract.represent(contrato, type: :full, admin: true)
        end

        desc 'Corrige o texto de uma versão' do
          detail 'DEC-80 recusou o versionamento imutável: o documento continua editável no lugar. ' \
                 'Tipo e número NÃO mudam — para isso, publique uma versão nova.'
        end
        params do
          requires :id, type: String
          optional :title, type: String
          optional :description, type: String
        end
        put ':id' do
          authorize!('contract_versions', :update)
          contrato = find_version!

          contrato.title = params[:title] if params.key?(:title) && params[:title].present?
          contrato.description = params[:description] if params.key?(:description) && params[:description].present?

          unless contrato.save
            error!({ error: 'invalid', message: contrato.errors.full_messages.to_sentence,
                     details: contrato.errors.messages }, 422)
          end

          Api::Entities::Contract.represent(contrato, type: :full, admin: true)
        end

        desc 'Remove uma versão' do
          detail 'Recusado quando a versão já tem aceite gravado: apagar apagaria a prova junto (DEC-80).'
        end
        params { requires :id, type: String }
        delete ':id' do
          authorize!('contract_versions', :destroy)
          contrato = find_version!

          if contrato.contract_deals.exists?
            error!({ error: 'has_acceptances',
                     message: 'Esta versão já tem aceites gravados e não pode ser removida — a prova ' \
                              'de aceite seria apagada junto.',
                     code: 'CONTRACT_HAS_ACCEPTANCES' }, 422)
          end

          contrato.destroy!
          { success: true }
        end
      end
    end
  end
end

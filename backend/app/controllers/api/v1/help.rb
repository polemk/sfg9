# frozen_string_literal: true

module Api
  module V1
    # S12 / BE-350..BE-363, OPS-545 — **a central de ajuda, o FAQ e a ajuda de
    # campo**.
    #
    # ## Autorização (BE-363 / D-57)
    #
    # No legado **os 4 controllers de help respondiam sem usuário logado** — não
    # sobrescreviam `requires_current_user?`. Só o CSRF protegia as escritas, e a
    # única restrição real era **de menu**: quem digitasse a URL fazia tudo.
    #
    # Aqui: sessão obrigatória em tudo; leitura do FAQ para qualquer autenticado
    # (`faq`, `R R R R` na matriz); escrita da central só para papel
    # administrativo (`help_items`/`help_categories`/`help_groups`, `CRUD CRUD - R`).
    # O gate é do servidor, não do menu.
    #
    # ## As rotas mortas que NÃO são portadas (BE-364 — ID de S14)
    #
    # `Pub::HelpController` não tem rota alguma e renderiza diretórios
    # inexistentes; as três actions `#index` renderizam template inexistente, de
    # modo que `GET /help_items`, `/help_categories` e `/help_groups` retornam
    # **500**. No Grape isso é estruturalmente impossível: só rota declarada
    # existe. A evidência do descarte é registrada pela S14, dona do ID.
    class Help < Grape::API
      helpers Api::V1::ControllerHelpers

      helpers do
        def find_group!
          registro = HelpGroup.find_by(id: params[:id])
          # BE-359: no legado era `.where(...).first` seguido de `.update` —
          # `nil.update` estourava `NoMethodError` e o cliente via **500**.
          error!({ error: 'not_found', message: 'Grupo não encontrado.' }, 404) if registro.nil?
          registro
        end

        def find_category!(id = params[:id])
          registro = HelpCategory.find_by(id: id)
          error!({ error: 'not_found', message: 'Categoria não encontrada.' }, 404) if registro.nil?
          registro
        end

        def find_item!
          # BE-353: o `fetch_help_item` do legado tinha o fallback
          # `params[:account_id]` — resíduo de copy/paste de outro CRUD. Não é
          # portado: um id de conta jamais deveria endereçar um item de ajuda.
          registro = HelpItem.find_by(id: params[:id])
          error!({ error: 'not_found', message: 'Item não encontrado.' }, 404) if registro.nil?
          registro
        end

        def item_errors!(item)
          error!({ error: 'invalid', message: item.errors.full_messages.to_sentence,
                   details: item.errors.messages }, 422)
        end
      end

      # =====================================================================
      # FAQ — leitura, para qualquer autenticado
      # =====================================================================
      namespace :faq do
        before { authenticate_user! }

        desc 'A árvore de grupos e categorias do FAQ'
        get '' do
          authorize!('faq', :read)
          Api::Entities::HelpGroup.represent(
            HelpGroup.ordered.includes(categories: :items), with_categories: true
          )
        end

        desc 'Itens de UMA categoria' do
          detail 'BE-350 — categoria é OBRIGATÓRIA. No legado, ausente virava `where(help_category_id: nil)`, ' \
                 'zero itens e a tela dizendo "nenhum resultado": mentira sobre o acervo.'
        end
        params do
          requires :category_id, type: String
          optional :q, type: String
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get 'items' do
          authorize!('faq', :read)
          categoria = find_category!(params[:category_id])

          escopo = ::Help::Search.in_category(categoria, term: params[:q])
          Api::Entities::HelpItem.represent(paginate(escopo), term: params[:q], type: :full)
        end

        desc 'Busca em TODO o acervo do FAQ' do
          detail 'BE-350 / D-58 — a busca olha o CONTEÚDO RICO. Item de 2018 (coluna) e de 2024 (ActionText) ' \
                 'abrem do mesmo campo e são achados pela mesma consulta. O termo `0` não casa a base inteira: ' \
                 'não existe `OR id = q.to_i`.'
        end
        params do
          requires :q, type: String
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get 'search' do
          authorize!('faq', :read)

          escopo = ::Help::Search.all(term: params[:q]).includes(category: :group)
          Api::Entities::HelpItem.represent(paginate(escopo), term: params[:q])
        end

        desc 'Um item do FAQ'
        params { requires :id, type: String }
        get 'items/:id' do
          authorize!('faq', :read)
          Api::Entities::HelpItem.represent(find_item!, type: :full)
        end
      end

      # =====================================================================
      # Ajuda de campo (OPS-545 / DEC-88) — o MECANISMO
      # =====================================================================
      namespace :help do
        before { authenticate_user! }

        desc 'Textos de ajuda de campo, por formulário' do
          detail 'DEC-88 — os 91 textos foram escritos e vivem em `db/seed_assets/*_help_inputs.yml`. ' \
                 'As 4 chaves marcadas `TODO:` NÃO são devolvidas: campo sem resposta não ganha tooltip.'
        end
        params do
          optional :scope, type: String, values: ::Help::FieldHelp::SCOPES
        end
        get 'fields' do
          authorize!('help', :read)

          if params[:scope].present?
            { params[:scope] => ::Help::FieldHelp.for_scope(params[:scope]) }
          else
            ::Help::FieldHelp.all
          end
        end
      end

      # =====================================================================
      # Central administrativa — grupos
      # =====================================================================
      namespace :help_groups do
        before { authenticate_user! }

        desc 'A árvore inteira, com contagem de itens'
        get '' do
          authorize!('help_groups', :read)
          ::Help::Tree.call.map do |no|
            Api::Entities::HelpGroup.represent(no[:group]).as_json.merge(
              categories: no[:categories].map do |c|
                Api::Entities::HelpCategory.represent(c[:category], items_count: c[:items_count]).as_json
              end
            )
          end
        end

        desc 'Cria um grupo' do
          detail 'BE-358 — `user_id` NÃO entra: a tabela `help_groups` não tem essa coluna, e um formulário ' \
                 'que a enviasse causaria `UnknownAttributeError`. Título único no BANCO.'
        end
        params do
          requires :title, type: String
          optional :position, type: Integer
        end
        post '' do
          authorize!('help_groups', :create)
          grupo = HelpGroup.new(declared(params, include_missing: false).symbolize_keys)
          unless grupo.save
            error!({ error: 'invalid', message: grupo.errors.full_messages.to_sentence,
                     details: grupo.errors.messages }, 422)
          end

          status 201
          Api::Entities::HelpGroup.represent(grupo)
        end

        desc 'Renomeia ou reordena um grupo'
        params do
          requires :id, type: String
          optional :title, type: String
          optional :position, type: Integer
        end
        put ':id' do
          authorize!('help_groups', :update)
          grupo = find_group!
          grupo.assign_attributes(declared(params, include_missing: false).symbolize_keys.except(:id))
          unless grupo.save
            error!({ error: 'invalid', message: grupo.errors.full_messages.to_sentence,
                     details: grupo.errors.messages }, 422)
          end

          Api::Entities::HelpGroup.represent(grupo)
        end

        desc 'O que se perde ao apagar este grupo' do
          detail 'BE-360 — a contagem da subárvore vem do SERVIDOR. No legado o único aviso era texto fixo no JS.'
        end
        params { requires :id, type: String }
        get ':id/impact' do
          authorize!('help_groups', :read)
          ::Help::Tree.group_impact(find_group!)
        end

        desc 'Apaga o grupo em cascata dupla, numa transação'
        params { requires :id, type: String }
        delete ':id' do
          authorize!('help_groups', :destroy)
          grupo = find_group!
          impacto = ::Help::Tree.destroy_group!(grupo)
          { success: true, deleted: impacto }
        end
      end

      # =====================================================================
      # Central administrativa — categorias
      # =====================================================================
      namespace :help_categories do
        before { authenticate_user! }

        desc 'Cria uma categoria' do
          detail 'BE-355 — título único NO GRUPO, garantido pelo banco. Campos não declarados (`is_editing`) ' \
                 'são ignorados sem erro, porque o Grape só entrega o que foi declarado.'
        end
        params do
          requires :help_group_id, type: String
          requires :title, type: String
          optional :position, type: Integer
        end
        post '' do
          authorize!('help_categories', :create)
          find_group_id = HelpGroup.find_by(id: params[:help_group_id])
          error!({ error: 'not_found', message: 'Grupo não encontrado.' }, 404) if find_group_id.nil?

          categoria = HelpCategory.new(declared(params, include_missing: false).symbolize_keys)
          unless categoria.save
            error!({ error: 'invalid', message: categoria.errors.full_messages.to_sentence,
                     details: categoria.errors.messages }, 422)
          end

          status 201
          Api::Entities::HelpCategory.represent(categoria)
        end

        desc 'Renomeia a categoria ou a MOVE de grupo' do
          detail 'BE-356 — mover leva os itens junto (eles pertencem à categoria). O `slug` NÃO muda ao ' \
                 'renomear: é deep-link, e mudá-lo quebraria o link de quem salvou.'
        end
        params do
          requires :id, type: String
          optional :title, type: String
          optional :help_group_id, type: String
          optional :position, type: Integer
        end
        put ':id' do
          authorize!('help_categories', :update)
          categoria = find_category!

          if params[:help_group_id].present? && HelpGroup.find_by(id: params[:help_group_id]).nil?
            error!({ error: 'not_found', message: 'Grupo não encontrado.' }, 404)
          end

          categoria.assign_attributes(declared(params, include_missing: false).symbolize_keys.except(:id))
          unless categoria.save
            error!({ error: 'invalid', message: categoria.errors.full_messages.to_sentence,
                     details: categoria.errors.messages }, 422)
          end

          Api::Entities::HelpCategory.represent(categoria)
        end

        desc 'O que se perde ao apagar esta categoria'
        params { requires :id, type: String }
        get ':id/impact' do
          authorize!('help_categories', :read)
          ::Help::Tree.category_impact(find_category!)
        end

        desc 'Apaga a categoria em cascata, numa transação'
        params { requires :id, type: String }
        delete ':id' do
          authorize!('help_categories', :destroy)
          impacto = ::Help::Tree.destroy_category!(find_category!)
          { success: true, deleted: impacto }
        end
      end

      # =====================================================================
      # Central administrativa — itens
      # =====================================================================
      namespace :help_items do
        before { authenticate_user! }

        desc 'Busca administrativa, em todos os grupos' do
          detail 'BE-351 — devolve a CONTAGEM TOTAL no envelope. Sem ela o front do legado pedia `l = 30` ' \
                 'e qualquer instalação com mais de 30 itens perdia itens em silêncio na tela.'
        end
        params do
          optional :q, type: String
          optional :category_id, type: String
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!('help_items', :read)

          escopo = ::Help::Search.all(term: params[:q]).includes(category: :group)
          escopo = escopo.where(help_category_id: params[:category_id]) if params[:category_id].present?
          Api::Entities::HelpItem.represent(paginate(escopo), term: params[:q])
        end

        desc 'Um item, com o texto'
        params { requires :id, type: String }
        get ':id' do
          authorize!('help_items', :read)
          Api::Entities::HelpItem.represent(find_item!, type: :full)
        end

        desc 'Cria um item' do
          detail 'BE-352 — CORPO VAZIO É REJEITADO. No legado `validates :description, presence: true` nunca ' \
                 'falhava: `has_rich_text` faz o leitor devolver um objeto novo, sempre "presente".'
        end
        params do
          requires :help_category_id, type: String
          requires :title, type: String
          requires :description, type: String, desc: 'HTML do corpo'
          optional :position, type: Integer
        end
        post '' do
          authorize!('help_items', :create)
          find_category!(params[:help_category_id])

          item = HelpItem.new(
            help_category_id: params[:help_category_id],
            title: params[:title],
            position: params[:position],
            # AUTOR: o da sessão, na CRIAÇÃO. Nunca vem do payload — era o campo
            # escondido do legado (FE-366).
            user_id: acting_user&.id,
            last_updated_user_id: acting_user&.id
          )
          item.description = params[:description]
          item_errors!(item) unless item.save

          status 201
          Api::Entities::HelpItem.represent(item, type: :full)
        end

        desc 'Edita um item' do
          detail 'FE-366 — a AUTORIA é preservada. No legado o `user_id` viajava em campo escondido com o ' \
                 '`current_user`, e editar item de outro autor reescrevia a autoria.'
        end
        params do
          requires :id, type: String
          optional :title, type: String
          optional :description, type: String
          optional :help_category_id, type: String
          optional :position, type: Integer
        end
        put ':id' do
          authorize!('help_items', :update)
          item = find_item!

          find_category!(params[:help_category_id]) if params[:help_category_id].present?

          item.title = params[:title] if params[:title].present?
          item.help_category_id = params[:help_category_id] if params[:help_category_id].present?
          item.position = params[:position] if params[:position].present?
          item.description = params[:description] if params[:description].present?
          # Quem alterou por último vai em coluna PRÓPRIA. `user_id` (o autor)
          # não é tocado.
          item.last_updated_user_id = acting_user&.id

          item_errors!(item) unless item.save
          Api::Entities::HelpItem.represent(item, type: :full)
        end

        desc 'Apaga um item' do
          detail 'BE-354 — falha responde ERRO COM MOTIVO. No legado o ternário era ' \
                 '`@help_item.errors.any? ? :ok : :ok` (200 sempre) e o template de resposta tinha 0 bytes.'
        end
        params { requires :id, type: String }
        delete ':id' do
          authorize!('help_items', :destroy)
          item = find_item!

          unless item.destroy
            error!({ error: 'delete_failed',
                     message: item.errors.full_messages.to_sentence.presence ||
                              'Não foi possível excluir o item.' }, 422)
          end

          { success: true }
        end
      end
    end
  end
end

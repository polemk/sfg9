# frozen_string_literal: true

module Api
  module V1
    # Leitura da trilha de auditoria — `BE-432` (listagem filtrável) e o detalhe.
    #
    # A trilha é o `paper_trail` (DEC-59): **uma** tabela `versions`, sem
    # `AuditEvent` e sem `trackings`. O payload é COMPLETO (DEC-78) — dá para
    # reconstruir o estado de qualquer registro em qualquer ponto do tempo.
    #
    # **`GET /api/v1/trackings` do legado não é portado como rota.** É esta rota.
    # O que o legado fazia aqui e não vem junto, com a evidência:
    #  - filtro por `target_id` e por `target_group_id`/`target_group_type`:
    #    **nenhum** dos 20 emissores do `TrackingFacade` escreve essas colunas;
    #  - `type`: coluna STI sempre `NULL`;
    #  - distância geográfica no detalhe (`BE-433`): descartada pelo **DEC-92**,
    #    que removeu a geolocalização inteira — a associação polimórfica não tem
    #    lado inverso nenhum no repositório de origem.
    #
    # **DEC-77 — quem lê.** A trilha GLOBAL (índice de tudo que aconteceu) é de
    # OG e Admin, e por isso é recurso próprio na matriz de autorização. O
    # histórico **do próprio objeto** é de quem vê o objeto, e por isso é
    # servido pelo endpoint do objeto, com `Sfg::AuditTrail.for_record`, e não
    # aqui.
    class AuditTrail < Grape::API
      helpers Api::V1::ControllerHelpers

      helpers do
        # Carrega os autores de uma página inteira num único SELECT. Sem isto a
        # entity faz um `find_by` por linha — 20 versões viram 40 consultas,
        # porque o impersonado também é usuário.
        def actors_for(versions)
          ids = versions.flat_map { |v| [v.whodunnit, v.impersonated_id] }.compact_blank.uniq
          return {} if ids.empty?

          ::User.where(id: ids).index_by { |u| u.id.to_s }
        end
      end

      namespace :audit_trail do
        before do
          authenticate_user!
          authorize!('audit_trail', :read)
        end

        desc 'Trilha de auditoria global' do
          summary 'Índice de versões'
          detail 'Paginação em cabeçalho. Filtros combináveis por tipo de registro, id, autor, evento e período.'
          success Api::Entities::AuditVersion
          failure [
            { code: 401, message: 'Não autenticado' },
            { code: 403, message: 'A trilha global é de OG e Admin (DEC-77)' }
          ]
        end
        params do
          optional :item_type, type: String, desc: 'Classe do registro (ex.: UserPermission)'
          optional :item_id, type: String, desc: 'Id do registro'
          optional :whodunnit, type: String, desc: 'Id do autor real do ato'
          # `impersonate_*` não vem do paper_trail: `Auth::ImpersonateService`
          # grava na MESMA tabela, porque a trilha é uma só (DEC-59). Sem
          # estarem aqui, o ato mais sensível do sistema não seria filtrável.
          optional :event, type: String,
                           values: %w[create update destroy impersonate_start impersonate_stop]
          # ISO-8601 na fronteira inteira (`FE-440`), e o tipo é `Sfg::Iso8601`
          # de propósito: o `DateTime` do Grape **aceita** `31/12/2025` e
          # `03/04/2026`, devolvendo 200 com a janela errada. Formato de data
          # ambíguo num filtro de auditoria é resposta errada com cara de certa.
          optional :from, type: DateTime, coerce_with: Sfg::Iso8601, desc: 'Início do período, ISO-8601'
          optional :to, type: DateTime, coerce_with: Sfg::Iso8601, desc: 'Fim do período, ISO-8601'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          versions = paginate(Sfg::AuditTrail.filter(params))

          Api::Entities::AuditVersion.represent(
            versions.to_a, actors: actors_for(versions)
          )
        end

        # Tipos com verbete no catálogo, para a tela montar o filtro sem
        # conhecer a lista de models do servidor.
        desc 'Tipos de registro presentes na trilha' do
          summary 'Vocabulário do filtro por tipo'
        end
        get 'types' do
          Sfg::AuditSummary.known_types.map do |tipo|
            { value: tipo, label: Sfg::AuditSummary.label_for(tipo) }
          end
        end

        desc 'Detalhe de uma versão' do
          summary 'Uma versão, com a foto completa do estado anterior'
          detail 'O `snapshot` só aparece aqui: na listagem, 20 fotos completas seriam um download.'
          success Api::Entities::AuditVersion
          failure [
            { code: 401, message: 'Não autenticado' },
            { code: 403, message: 'A trilha global é de OG e Admin (DEC-77)' },
            { code: 404, message: 'Versão inexistente' }
          ]
        end
        params do
          requires :id, type: Integer, desc: 'Id da versão'
        end
        get ':id' do
          version = PaperTrail::Version.find_by(id: params[:id])
          error!({ error: 'not_found', message: I18n.t('platform.not_found') }, 404) if version.nil?

          Api::Entities::AuditVersion.represent(
            version, detail: true, actors: actors_for([version])
          )
        end
      end
    end
  end
end

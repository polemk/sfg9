# frozen_string_literal: true

module Api
  module V1
    # S8 / **BE-280**…**BE-287**, **BE-291**, **FE-309**, **OPS-283**,
    # **OPS-288** — as **operações estruturadas** do projeto.
    #
    # ## A IDOR, literal
    #
    # `structured_operations_controller.rb:25`:
    #
    # ```ruby
    # @structured_operations = StructuredOperation.joins(...).where(project_id: ...)
    # @structured_operations = StructuredOperation.where(id: params[:structured_operation_id]) unless ...
    # ```
    #
    # A segunda linha **reatribui** a relation e o filtro de projeto some. O
    # parâmetro continua existindo aqui (o front o usa para "detalhe embutido"),
    # mas entra num `where` **dentro** do escopo — id de outro projeto devolve
    # vazio, nunca 403, que confirmaria a existência do registro alheio.
    #
    # ## A sentinela de ±2000 anos morre aqui (OPS-283 / IMP-R4)
    #
    # Sem `from`/`to`, o legado mandava `DateTime.dinosaurs` e `DateTime.mars` —
    # um monkey-patch — como limites do range. Aqui o predicado simplesmente
    # **não é aplicado**. O efeito é idêntico para dados com data preenchida; o
    # que muda é que **operação com data nula passa a aparecer**, em vez de ser
    # excluída em silêncio pelo `DATE(NULL)`.
    class StructuredOperations < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'structured_operations'

      namespace :structured_operations do
        before { authenticate_user! }

        desc 'Lista as operações estruturadas do projeto corrente' do
          summary 'Operações estruturadas'
          detail 'BE-284 — `X-Total-Count` traz o total **real**: no legado ele era calculado DEPOIS do ' \
                 '`limit!/offset!` e devolvia no máximo o tamanho da página, o que fazia toda a habilitação ' \
                 'de paginação da tela depender de um número truncado. `per_page` tem teto (o legado aceitava ' \
                 '`l=999999`).'
          success [code: 200, model: Api::Entities::StructuredOperation]
          is_array true
        end
        params do
          optional :q, type: String, desc: 'Busca em `carriers.title` OU `structured_operations.title` (BE-281)'
          optional :structured_operation_id, type: String, desc: 'Filtro por id — DENTRO do escopo (BE-280)'
          optional :company_id, type: String
          optional :carrier_id, type: String
          optional :operation_type_id, type: String
          optional :from, type: Date, desc: 'Início do período. Data malformada → 400.'
          optional :to, type: Date, desc: 'Fim do período. Sem `from`/`to` o predicado NÃO é aplicado.'
          optional :ordering_keys, type: Array[String], values: ::StructuredOperation::ORDERING.allowed.keys,
                                   desc: 'title | operation_type | carrier | contract_number | issue_date | ' \
                                         'operation_value | balance | due_date | agreed_rate. ' \
                                         'A chave `company` SAIU (B-13): não há coluna "Empresa" na tela.'
          optional :ordering_style, type: Array[String], values: %w[up down asc desc ascending descending]
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          project = current_project!

          scope = Structured::OperationService.index(project: project, params: params)[:data]
          Api::Entities::StructuredOperation.represent(paginate(scope).to_a)
        end

        desc 'Textos de ajuda dos campos do formulário' do
          detail 'OPS-284 — carregados **uma vez** (`Rails.cache`), não `YAML.load_file` por campo ' \
                 'renderizado. Arquivo ausente devolve `{}`; no legado sumir do deploy dava **500** no ' \
                 'formulário inteiro. As 13 chaves do legado têm todas o MESMO placeholder, então o ' \
                 'conteúdo nasce vazio (Q-R9) e **campo sem chave não exibe indicador de ajuda**.'
        end
        get 'help_texts' do
          authorize!(RESOURCE, :read)
          ::Structured::HelpTexts.all
        end

        desc 'Detalhe de uma operação' do
          detail 'FE-299 — id inexistente ou de outro projeto responde **404**, não 500.'
        end
        params { requires :id, type: String, desc: 'UUID do registro' }
        get ':id' do
          authorize!(RESOURCE, :read)
          project = current_project!

          result = Structured::OperationService.show(project: project, id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::StructuredOperation.represent(result[:data])
        end

        desc 'Cria uma operação estruturada' do
          detail 'BE-285 — `user_id` vem da SESSÃO e **`:id` está fora do permit** (permitir `id` no create é a ' \
                 'mesma família de mass assignment do D-60/D-68). `project_id` é DERIVADO da empresa e o do ' \
                 'corpo nem é declarado. `title` em branco recebe `carrier.title`. ' \
                 '**As validações ausentes continuam ausentes** (BE-293): sem `due_date >= issue_date`, sem ' \
                 '`operation_value > 0`, sem faixa de `agreed_rate`, sem unicidade de `contract_number`.'
        end
        params do
          requires :company_id, type: String
          requires :carrier_id, type: String
          requires :operation_type_id, type: String
          requires :issue_date, type: Date
          requires :due_date, type: Date
          requires :operation_value, type: BigDecimal
          optional :title, type: String, desc: 'Em branco recebe o título do portador'
          optional :contract_number, type: String
          optional :original_balance, type: BigDecimal, desc: 'Gravado NEGATIVO: `(-1) × |valor|` (DEC-01)'
          optional :agreed_rate, type: BigDecimal, desc: '**NÃO é a taxa que remunera** (BE-295)'
          optional :observation, type: String
          optional :is_on_variable, type: Boolean, default: false
          optional :is_ended, type: Boolean, default: false
          optional :confirm_project_change, type: Boolean, default: false,
                                            desc: 'BE-291 — exigido quando a empresa é de outro projeto'
        end
        post '' do
          authorize!(RESOURCE, :create)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys
          result = Structured::OperationService.create(project: project, attrs: attrs, actor: acting_user)
          error!(error_payload_for(result), result[:status]) if result[:status] != 201

          status 201
          Api::Entities::StructuredOperation.represent(result[:data])
        end

        desc 'Atualiza uma operação' do
          detail 'BE-286 — **um** save (o legado fazia três seguidos, reexecutando os callbacks 3×) e busca ' \
                 '**com** escopo de projeto. **T-D5**: `issue_date` e `due_date` são IMUTÁVEIS na edição, ' \
                 'no servidor — a tela as mostra readonly e agora o servidor concorda. ' \
                 'BE-292: qualquer update reseta `balance` para `original_balance`, inclusive editando só a ' \
                 'observação — replicado (golden E6).'
        end
        params do
          requires :id, type: String
          optional :title, type: String
          optional :company_id, type: String
          optional :carrier_id, type: String
          optional :operation_type_id, type: String
          optional :contract_number, type: String
          optional :operation_value, type: BigDecimal
          optional :original_balance, type: BigDecimal
          optional :agreed_rate, type: BigDecimal
          optional :observation, type: String
          optional :is_on_variable, type: Boolean
          optional :is_ended, type: Boolean
          optional :confirm_project_change, type: Boolean, default: false
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          project = current_project!

          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          result = Structured::OperationService.update(project: project, id: params[:id],
                                                       attrs: attrs, actor: acting_user)
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          Api::Entities::StructuredOperation.represent(result[:data])
        end

        desc 'Remove uma operação' do
          detail 'BE-287 — operação com recibo emitido responde **422 DE VERDADE**. No legado o ternário ' \
                 'degenerado `errors.any? ? :ok : :ok` respondia 200, o front recarregava a lista como sucesso ' \
                 'e a operação continuava lá.'
        end
        params { requires :id, type: String }
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          project = current_project!

          result = Structured::OperationService.destroy(project: project, id: params[:id])
          error!(error_payload_for(result), result[:status]) if result[:status] != 200
          result[:data]
        end
      end
    end
  end
end

# frozen_string_literal: true

# S4 / BE-059..BE-063, BE-065 — **fornecedores**.
#
# `title` e `integration_key` são obrigatórios **também no update** (BE-062): no
# legado o `update` chamava `Provider.update` e depois `save`, e a chave em
# branco passava porque a derivação só rodava `on: [:create]`.
class ProviderService < ProjectScopedService
  class << self
    def model = Provider
    def resource_label = 'Fornecedor'

    def writable_attributes
      %i[title resume integration_key is_active document_type document
         legal_name trade_name status opened_at status_changed_at email phone
         zip_code street number complement district city state activities
         cnpj_fetched_at]
    end

    def base_scope(project)
      model.for_project(project).with_attached_logo
    end

    def filter(scope, params)
      scope = scope.active if truthy?(params[:active])
      scope
    end

    # Anexa (ou remove) o logo do fornecedor. **Separado do `update`** e no
    # mesmo molde do portador: o `multipart` é outro caminho de requisição, e
    # misturar os dois obrigaria todo salvamento de formulário a ser multipart.
    def attach_logo_file(project:, id:, file:)
      record = find(project, id)
      return not_found if record.nil?

      record.logo.attach(io: file[:tempfile], filename: file[:filename], content_type: file[:type])
      # A validação de tipo REAL roda no `save` (Marcel/magic bytes): um `.exe`
      # renomeado para `.png` é recusado. No legado a detecção de spoof estava
      # desligada, e o Paperclip só olhava a extensão.
      unless record.save
        record.logo.purge
        return unprocessable(record)
      end

      { status: 200, data: record.reload }
    end

    def remove_logo(project:, id:)
      record = find(project, id)
      return not_found if record.nil?

      record.logo.purge_later if record.logo.attached?
      { status: 200, data: record.reload }
    end

  end
end

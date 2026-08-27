# frozen_string_literal: true

# S3 / BE-067..BE-071 — portadores.
#
# Três desvios do molde, e cada um é uma decisão registrada:
#
# 1. **`subordinated_accounts_percent` NÃO é gravável** (DC-09). Ele não está em
#    `writable_attributes` e o endpoint nem o declara: o número é derivado no
#    model a partir das cotas. No legado a coluna era editável **e** recalculada
#    em JS a cada tecla — duas fontes de verdade para o mesmo número.
# 2. **`group_id` filtra a lista** (BE-067). Um `group_id` inexistente devolve
#    **vazio**, nunca a lista inteira e nunca 500: o filtro entra no `where`,
#    não num `if` que some quando o id não casa.
# 3. **O logo é anexo do próprio model** (DEC-47/DEC-91), gravado aqui e não por
#    `Medium` nem pelo `assets_proxy_controller` (que não autentica nada — é
#    achado de base compartilhada, registrado em `upstream-flags.md`).
class CarrierService < CatalogService
  class << self
    def model = ::Carrier
    def resource_label = 'Portador'

    def writable_attributes
      %i[title resume integration_key is_active bank_code senior_accounts
         subordinated_accounts net_worth group_id financial_agent city uf]
    end

    # A coluna "# Projetos" da listagem (FE-060) conta **conexões de projeto**,
    # não a soma de tudo que bloqueia a exclusão: um portador com limite de
    # risco mas sem conexão não está em projeto nenhum, e mostrar "1" ali seria
    # mentira. Quando a S4 entregar `project_to_carrier_connections`, o número
    # passa a ser real sozinho.
    def usage_dependents
      model.blocking_dependents.slice('ProjectToCarrierConnection')
    end

    def filter(scope, params)
      # `group_id` presente ⇒ entra no `where`. Id que não existe devolve
      # conjunto vazio — que é a resposta certa, não "sem filtro".
      scope = scope.where(group_id: params[:group_id]) if params[:group_id].present?
      scope = scope.where(financial_agent: params[:financial_agent]) if params[:financial_agent].present?
      scope = scope.where(uf: params[:uf].to_s.upcase) if params[:uf].present?
      scope.includes(:group).with_attached_logo
    end

    # Anexa (ou remove) o logo do portador. Separado do `update` porque o
    # `multipart` é outro caminho de requisição, e misturar os dois obrigaria
    # todo salvamento de formulário a ser multipart.
    def attach_logo(id:, file:)
      record = find(id)
      return not_found if record.nil?

      record.logo.attach(io: file[:tempfile], filename: file[:filename], content_type: file[:type])
      # A validação de tipo REAL roda no `save` — o legado tinha a detecção de
      # spoof DESLIGADA (`MediaTypeSpoofDetector#spoofed? → false`) e aceitava um
      # `.exe` renomeado para `.png` (OPS-051).
      unless record.save
        record.logo.purge
        return unprocessable(record)
      end

      { status: 200, data: record.reload }
    end

    def remove_logo(id:)
      record = find(id)
      return not_found if record.nil?

      record.logo.purge_later if record.logo.attached?
      { status: 200, data: record.reload }
    end
  end
end

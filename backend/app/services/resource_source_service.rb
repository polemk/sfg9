# frozen_string_literal: true

# **DONA: S8** (`BE-308`, `BE-725`…`BE-729`, `DB-287`, `DB-288`, Q-R19).
#
# A S6 criou a tabela, o model e **só a leitura**, por dependência dura:
# `receivable_entries.resource_source_id` é obrigatório e está preenchido em
# **28.131 de 28.131** linhas de produção — sem um `GET` que popule o select, o
# formulário de borderô não pode ser enviado.
#
# **A S8 fecha o resto**: `create`, `update`, `destroy`, o painel lateral, o
# `show` com 404 estruturado e a decisão sobre `is_active`.
#
# ## Q-R19 — `is_active` continua NÃO filtrando o select do borderô
#
# É a decisão, não um esquecimento. A fonte de recurso é **classificatória**:
# não entra em nenhuma fórmula de tarifa, IOF, custo efetivo ou remuneração —
# varredura em `BE-308`. Se o select do borderô passasse a filtrar por ativa,
# desativar uma fonte tornaria **irreeditável** todo borderô histórico que a
# usa, porque o valor gravado sumiria das opções. O filtro existe na tela de
# **administração** (`?active=true`), que é outra coisa.
#
# ## BE-728 — a chave de integração é IMUTÁVEL, e agora está escrito
#
# No legado isso era **acidental**: `before_validation … on: [:create]` só
# derivava quando o campo vinha em branco, e o formulário não o mandava. Aqui é
# recusa explícita, porque **é a chave que os relatórios usam** para casar
# fonte com origem — renomear o título não pode mexer nela, e mudá-la à mão
# quebraria a conciliação em silêncio.
class ResourceSourceService < CatalogService
  # Estas fontes são **dado migrado de um sistema anterior** (o Django, via
  # `durecliq.url_id` → `legacy_id`). Trocar a chave de uma linha importada
  # desfaz o de-para que provou a proveniência.
  KEY_IMMUTABLE = 'A chave de integração de uma fonte de recurso não pode ser alterada: ' \
                  'é ela que os relatórios usam para casar a fonte com a origem do recurso.'

  class << self
    def model = ::ResourceSource
    def resource_label = 'Fonte de recurso'
    def resource_genero = :feminino

    def writable_attributes
      %i[title integration_key is_active]
    end

    def update(id:, attrs:, actor: nil)
      return { status: 422, error: KEY_IMMUTABLE } if attrs.key?(:integration_key)

      super
    end
  end
end

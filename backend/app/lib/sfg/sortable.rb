# frozen_string_literal: true

module Sfg
  # Ordenação multi-coluna dirigida pelo cliente — `BE-449`.
  #
  # **O que o legado faz.** O cliente manda dois arrays PARALELOS,
  # `ordering_keys[]` e `ordering_style[]` (`movement_kinds_controller.rb:14-15`),
  # e o model os casa por índice para montar uma string de `ORDER BY`
  # (`movement_kind.rb:50-58`). Esse trio de métodos — `prepare_ordering`,
  # `get_ordering_key`, `get_ordering_style` — está copiado, idêntico, em
  # **18 models**: `movement_kind`, `sub_segment`, `segment`, `risk_operation`,
  # `renegotiation`, `carrier`, `wallet`, `indicator`, `provider`,
  # `receivable_kind`, `receivable_entry`, `resource_source`,
  # `structured_operation`, `structured_operation_type`, `risk_movement_type`,
  # `risk_operation_type`, `project_guarantee`, `project_guarantee_type`.
  # Muda só o `case` da allowlist. É o mesmo utilitário 18 vezes, e é por isso
  # que ele nasce aqui em vez de nascer de novo em cada fatia — a S6 é apenas o
  # primeiro consumidor.
  #
  # **Três coisas mudam, e as três são defeito medido:**
  #
  # 1. **Chave desconhecida derruba o request.** No legado `get_ordering_key`
  #    devolve `nil` para o que não está no `case`, e a linha seguinte faz
  #    `nil + " "` → `NoMethodError` → 500. Um `?ordering_keys[]=x` na barra de
  #    endereço basta. Aqui chave fora da allowlist é **ignorada**, e se sobrar
  #    nenhuma vale a ordem padrão.
  # 2. **Estilo desconhecido também.** `get_ordering_style` só conhece `"up"` e
  #    `"down"`; qualquer outra coisa devolve `nil` e produz `"title " + nil`.
  #    Aqui o padrão é `:asc`.
  # 3. **O `ORDER BY` deixa de ser string.** Sai um Hash/Arel, não um fragmento
  #    concatenado. Hoje a allowlist do legado é por acidente (os `when`
  #    devolvem literais); trocar um literal por interpolação em qualquer um dos
  #    18 arquivos abre injeção, e ninguém revisaria os 18.
  #
  # Uso:
  #
  #     ORDENACAO = Sfg::Sortable.new(
  #       allowed: { 'title' => :title, 'key' => :integration_key },
  #       default: { title: :asc }
  #     )
  #
  #     ORDENACAO.apply(MovementKind.all, keys: params[:ordering_keys],
  #                                       styles: params[:ordering_style])
  class Sortable
    STYLES = {
      'up' => :asc, 'asc' => :asc, 'ascending' => :asc,
      'down' => :desc, 'desc' => :desc, 'descending' => :desc
    }.freeze

    DEFAULT_STYLE = :asc

    # Teto de colunas por requisição. Sem ele, `ordering_keys[]` repetido mil
    # vezes vira um `ORDER BY` de mil termos — barato de mandar, caro de rodar.
    MAX_COLUMNS = 5

    attr_reader :allowed, :default

    # `allowed` mapeia a chave PÚBLICA (o que o cliente manda) para a coluna
    # real. Os dois lados existem de propósito: o nome da coluna é detalhe do
    # esquema, e o cliente não deve depender dele para ordenar.
    def initialize(allowed:, default: nil)
      @allowed = allowed.transform_keys(&:to_s).freeze
      @default = default
    end

    def apply(scope, keys:, styles: nil)
      ordem = build(keys, styles)
      return default ? scope.order(default) : scope if ordem.empty?

      scope.order(ordem)
    end

    # Devolve o Hash de ordenação já saneado — exposto para quem precisa
    # inspecionar (teste, log) sem aplicar.
    def build(keys, styles)
      chaves = Array(keys).map(&:to_s)
      estilos = Array(styles).map(&:to_s)

      chaves.each_with_index.filter_map { |chave, i|
        coluna = allowed[chave]
        next if coluna.nil?

        [coluna, STYLES.fetch(estilos[i].to_s.downcase, DEFAULT_STYLE)]
      }.first(MAX_COLUMNS).to_h
    end

    # Chaves recusadas — para devolver aviso ao cliente quando a tela quiser
    # dizer "esta coluna não ordena" em vez de ordenar silenciosamente por outra.
    def rejected(keys)
      Array(keys).map(&:to_s).reject { |chave| allowed.key?(chave) }
    end
  end
end

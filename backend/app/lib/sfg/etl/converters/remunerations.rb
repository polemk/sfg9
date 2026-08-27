# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `remunerations` (legado) -> `Remuneration` (ai9). **S8.**
      #
      # ## ⚠ A TABELA NÃO EXISTE NA ORIGEM DE PRODUÇÃO — DEC-103b
      #
      # `20220629123512_create_remunerations` (mais o
      # `20220802165837_add_title_to_remuneration`) está entre as **24 migrations
      # que nunca subiram**. Conferido no dump de 31/05/2025: a relação não
      # existe. **O faturamento por tipo de operação nunca rodou em produção.**
      # Zero linha lida é o resultado esperado.
      #
      # ## ⚠ `operation_type_id` é POLIMÓRFICO — e o de-para depende do TIPO
      #
      # Esta é a segunda tabela da migração (depois de `action_text_rich_texts`)
      # cuja FK aponta para **tabelas diferentes linha a linha**:
      # `operation_type_type` diz se o `operation_type_id` está em
      # `risk_operation_types` ou em `structured_operation_types`.
      #
      # Por isso `references` fica **vazia**: o motor não consegue contar órfão
      # por uma coluna cujo destino muda a cada linha. O religamento é feito aqui,
      # escolhendo a tabela pelo tipo, e a conferência vive em `anomalies` —
      # exatamente o desenho de `Converters::ActionTextRichTexts`.
      #
      # **Tipo fora das duas classes NÃO vira `nil` em silêncio.** No legado
      # `operation_class` devolvia `nil` e `beauty_type` devolvia a string
      # `"???"` (`../sfg/app/models/remuneration.rb:35,44`) — o valor arbitrário
      # entrava e quebrava depois, longe da causa. No ai9 há `check_constraint` no
      # banco: a linha seria recusada no meio da carga. Aqui ela é declarada antes.
      #
      # ## `value` é FLOAT na origem e `decimal(7,4)` no destino — e é ELA que multiplica tudo
      #
      # A taxa, em %. **Sem validação de faixa** (DEC-37/T-D9): 250% passa hoje e
      # continua passando — é decisão registrada, não descuido. E é a mesma escala
      # de `receipts.fee`, que a copia. `Values.to_decimal` faz o cast sem
      # arredondamento extra, como manda a DEC-02.
      #
      # ## `title` é DESNORMALIZADO de propósito, e o model o reescreve
      #
      # Decisão B-06 / DB-285: é a coluna que a busca textual usa
      # (`remunerations_controller.rb:14`). `Remuneration#copy_title_from_operation_type`
      # roda em **todo save, sem `on:`** (BE-304), copiando de
      # `operation_type.title`. O conversor traz o título da origem para o
      # relatório ter o que comparar, mas quem manda é o model — daí a declaração
      # em `derived`.
      #
      # ## `user_id` não existe na origem
      #
      # No legado a coluna não existe e `user_id` sequer estava no `permit`. Entra
      # **NULO**: não há de onde tirá-lo, e escolher alguém seria inventar autoria
      # — o defeito que o ETL de 2021 deixou em portadores e recebíveis
      # (BE-452 (a)) e que esta migração não repete.
      class Remunerations < Base
        # `operation_type_type` do legado => tabela da origem cujo de-para resolve
        # o tipo. Fora desta tabela **nada é convertido**.
        OWNERS = {
          'RiskOperationType' => 'risk_operation_types',
          'StructuredOperationType' => 'structured_operation_types'
        }.freeze

        def self.source_table = 'remunerations'
        def self.target_model = 'Remuneration'
        def self.requires = %w[Remuneration Project]
        def self.owner_slice = 'S8'
        # `project_id` é a ÚNICA referência que o motor consegue conferir: a outra
        # é polimórfica. Ver o bloco acima.
        def self.references = { 'project_id' => 'projects' }
        # DB-284 — o índice único composto que fecha a corrida que a validação de
        # aplicação do legado (`remuneration.rb:11`) não via, e que garante que
        # `Receipt#fetch` (um `.first`) ache UMA taxa.
        def self.uniques = [%w[project_id operation_type_type operation_type_id]]
        # Reescrito pelo model em todo save (BE-304).
        def self.derived = %w[title]

        def convert(row)
          tipo = row['operation_type_type'].to_s
          tabela = OWNERS[tipo]
          {
            project_id: ref('projects', row['project_id']),
            operation_type_type: OWNERS.key?(tipo) ? tipo : nil,
            operation_type_id: tabela && ref(tabela, row['operation_type_id']),
            # DEC-37/T-D9 — sem validação de faixa, de propósito. DEC-02 — cast
            # sem arredondamento extra.
            value: Values.to_decimal(row['value']),
            title: row['title'],
            # A coluna não existe na origem. Inventar autoria é o defeito de 2021.
            user_id: nil,
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        def anomalies(row)
          tipo = row['operation_type_type'].to_s
          tabela = OWNERS[tipo]

          if tabela.nil?
            return [{ key: 'remunerations:unknown_operation_type',
                      title: 'Remuneração de um tipo de operação que o ai9 não conhece — o legado ' \
                             'aceitava valor arbitrário e devolvia `"???"`; aqui há `check_constraint`',
                      line: "- pk=#{row['id']} `operation_type_type` = #{tipo.inspect}" }]
          end

          return [] unless ref(tabela, row['operation_type_id']).nil?

          [{ key: 'remunerations:operation_type_not_loaded',
             title: 'Remuneração cujo TIPO ainda não está no de-para — carregue ' \
                    'os catálogos de tipo antes (a referência é polimórfica e o motor não a confere)',
             line: "- pk=#{row['id']} #{tipo}##{row['operation_type_id']}" }]
        end
      end
    end
  end
end

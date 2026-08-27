# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `indicators` (legado) -> `Indicator` (ai9). S10.
      #
      # Quatro coisas que só este conversor sabe:
      #
      # **1. O título chega em CAIXA ALTA sem acento — e continua assim (DEC-89).**
      # `../sfg/app/models/indicator.rb:39` faz `I18n.transliterate(title).upcase`
      # num `before_validation` **sem `on:`**, ou seja em todo save, desde 2021. Os
      # acentos do dado legado **já se perderam de forma irreversível**;
      # "re-humanizar" na carga seria adivinhação. `Values.indicator_title` aplica a
      # mesma transformação, para que o dado migrado e o digitado depois saiam do
      # mesmo lugar. O `before_validation` do model faria isso de qualquer forma —
      # está aqui explícito porque o ETL não deve depender de callback para produzir
      # o valor que a reconciliação vai comparar.
      #
      # **2. `is_active` é `= 1`, NÃO `≠ 0`.** No legado a coluna é
      # `integer default 1`, e as duas leituras que existem comparam com 1:
      # `is_active?` (`indicator.rb:83-85`) e o filtro da grade
      # (`indicator_entries_controller.rb:23`, `where(is_active: 1)`). Um
      # `is_active = 2` conta como **inativo** nas duas. `Values.to_boolean` reporta
      # como anomalia todo valor fora de {0,1}, que é justamente o que se quer ver
      # no dry-run.
      #
      # **3. `discarded_at` nasce nulo.** A exclusão lógica é feature nova desta
      # fatia (D-66); não há coluna equivalente na origem, e nenhum registro
      # migrado chega descartado. Registros que alguém apagou no legado
      # **não existem mais lá** — o `delete_all` levou o indicador e a série junto,
      # e não há de onde recuperá-los. É a perda que a exclusão lógica impede
      # daqui para frente, não uma que a carga conserte.
      #
      # **4. ⚠ A "Instrução" NÃO viaja nesta tabela.** Ela é ActionText: vive em
      # `action_text_rich_texts` com `record_type = 'Indicator'`. **Sem carregar
      # aquela tabela junto, o conteúdo se perde** — e os corpos podem estar
      # URL-escapados (é por isso que as views de contrato do legado fazem
      # `CGI.unescape`), então a codificação precisa ser validada **item por item**,
      # não em lote. Ver o runbook do ETL.
      class Indicators < Base
        def self.source_table = 'indicators'
        def self.target_model = 'Indicator'
        def self.owner_slice = 'S10'
        def self.references = { 'project_id' => 'projects' }
        def self.booleans = %w[is_active]

        # **`key` NÃO entra aqui, de propósito.** Ela não é única no legado
        # (DEC-85 / T-D13: nada dentro do repositório a lê, e não há como confirmar
        # de dentro do código se há BI ou planilha lendo do lado de fora). Declarar
        # a unicidade faria o motor bloquear a carga por duplicatas que são
        # legítimas na origem.
        #
        # O que É único: título por alcance. Mas as três regras do legado
        # (`indicator.rb:12-23`) não cabem numa tupla de colunas — a (a) compara
        # global contra TODOS, inclusive específicos. `anomalies` abaixo faz a
        # contagem que o motor faria, com a regra certa.
        def self.uniques = []

        def convert(row)
          {
            project_id: ref('projects', row['project_id']),
            title: Values.indicator_title(row['title']),
            key: row['key'],
            value_type: row['value_type'].presence || Indicator::VALUE_TYPE_MONEY,
            is_active: Values.to_boolean(row['is_active']).value,
            discarded_at: nil,
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        # As três regras de unicidade do legado, aplicadas à ORIGEM.
        #
        # Não é redundância com a validação do model: o motor grava com
        # `find_or_initialize_by` e a validação **reprovaria a segunda linha
        # silenciosamente na contagem**. Aqui a colisão aparece no relatório do
        # dry-run com o par de ids, para alguém decidir qual fica — que é a única
        # decisão possível, porque as duas linhas são dado real de produção.
        def anomalies(row)
          titulo = Values.indicator_title(row['title'])
          return [] if titulo.blank?

          conflitos = homonimos_por_titulo[titulo].to_a
                                                  .reject { |outra| outra['id'] == row['id'] }
                                                  .select { |outra| colide?(row, outra) }
          return [] if conflitos.empty?

          [Values.anomaly_line(
            "título duplicado pelas regras de unicidade do legado (ids #{conflitos.map { |c| c['id'] }.join(', ')})",
            'indicators', row['id'], 'title', row['title']
          )]
        end

        private

        # Índice título normalizado => linhas, montado UMA vez. Sem ele a
        # verificação seria O(n²) — e o `anomalies` roda linha a linha.
        def homonimos_por_titulo
          @homonimos_por_titulo ||= source.ordered_rows(self.class.source_table)
                                          .group_by { |r| Values.indicator_title(r['title']) }
        end

        # (a) global colide com QUALQUER outro de mesmo título — inclusive
        #     específico (é o efeito colateral replicado da regra do legado);
        # (b)/(c) específico colide com global, ou com específico do mesmo projeto.
        def colide?(row, outra)
          return true if row['project_id'].blank?

          outra['project_id'].blank? || outra['project_id'].to_s == row['project_id'].to_s
        end
      end
    end
  end
end

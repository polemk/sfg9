# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `project_to_carrier_connections` (legado) -> `ProjectToCarrierConnection` (ai9). **S4.**
      #
      # ## A ponte que decide o que aparece em três formulários
      #
      # 1.177 linhas em produção (medido no dump de 31/05/2025) — é a terceira
      # maior tabela do bloco de estrutura, e **ninguém a olha diretamente**. O
      # que ela decide é quais portadores aparecem no formulário de garantia
      # (BE-119), no de limite de risco (S5) e em `Company#carriers`, que é
      # `through: :project`. Perder uma linha aqui não dá erro nenhum: dá um
      # select mais curto do que devia, e ninguém percebe.
      #
      # ## ⚠ A ARMADILHA: a origem tem `legacy_id` PRÓPRIA, e ela é NULA em 403 linhas
      #
      # Esta tabela carrega **três** colunas de proveniência de uma migração
      # ANTERIOR à nossa (`legacy_id`, `legacy_project_id`, `legacy_carrier_id`,
      # do sistema `fbancoproj`), e o `schema.rb` do ai9 reproduz as três com o
      # mesmo nome. É convite a copiar `legacy_id` em `legacy_id` — e isso
      # quebra a carga de duas formas de uma vez:
      #
      # * **medido**: `legacy_id` está preenchida em **774 de 1.177** linhas.
      #   As outras **403** são nulas. O `legacy_id` do ai9 tem índice ÚNICO e é
      #   a **chave natural** deste conversor (`natural_key`): 403 nulos fazem
      #   `find_or_initialize_by(legacy_id: nil)` casar todas com a mesma linha,
      #   e a carga terminaria com 775 registros em vez de 1.177;
      # * o **de-para** (`etl_id_map`) é indexado pelo `id` da origem. Gravar
      #   outra proveniência na coluna faria o `reconcile` deixar de fechar.
      #
      # Então: **`legacy_id` do ai9 recebe `project_to_carrier_connections.id`**
      # — proveniência NESTA migração, que é o que a DEC-12 define. As duas
      # colunas `legacy_project_id`/`legacy_carrier_id` recebem as homônimas da
      # origem, preservando a proveniência do `fbancoproj` **sem disputar** a
      # coluna que o de-para usa. Mesma decisão, mesmo motivo, que
      # `Converters::ResourceSources` registra para a coluna `legacy_id` dela.
      #
      # O `legacy_id` próprio da origem é **descartado de propósito**: guardá-lo
      # exigiria uma quarta coluna, e ninguém no ai9 o lê. O que ele contava —
      # de onde a linha veio no sistema de 2021 — continua contado por
      # `legacy_project_id`/`legacy_carrier_id`.
      #
      # ## Integridade medida, e por isso não há anomalia declarada
      #
      # Contra o dump de 31/05/2025: **0** `project_id` nulo, **0** `carrier_id`
      # nulo, **0** órfão dos dois lados e **0** duplicata em
      # `(project_id, carrier_id)` — a unicidade que no legado era só validação
      # de aplicação (`project_to_carrier_connection.rb:7`) e que no ai9 é
      # índice do banco. As 1.177 linhas cabem na restrição nova como estão.
      # A declaração de `uniques` fica: ela existe para o dia em que não couberem.
      #
      # ## Não há `user_id` nem `is_active`
      #
      # Nem na origem nem no destino. A conexão é um fato binário — existe ou
      # não existe. Desligá-la é apagá-la, e é assim nos dois lados.
      class ProjectToCarrierConnections < Base
        def self.source_table = 'project_to_carrier_connections'
        def self.target_model = 'ProjectToCarrierConnection'
        def self.requires = %w[ProjectToCarrierConnection Project Carrier]
        def self.owner_slice = 'S4'
        def self.references = { 'project_id' => 'projects', 'carrier_id' => 'carriers' }
        def self.uniques = [%w[project_id carrier_id]]

        def convert(row)
          {
            project_id: ref('projects', row['project_id']),
            carrier_id: ref('carriers', row['carrier_id']),
            # DEC-12 — proveniência NESTA migração. Ver o bloco da armadilha acima:
            # NÃO é o `legacy_id` que a própria origem carrega.
            legacy_id: row['id'],
            # Proveniência do `fbancoproj`, herdada da migração de 2021. Nula em
            # 403 das 1.177 linhas, e é por isso que ela não serve de chave.
            legacy_project_id: row['legacy_project_id'],
            legacy_carrier_id: row['legacy_carrier_id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end
      end
    end
  end
end

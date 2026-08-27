# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `project_guarantees` (legado) -> `ProjectGuarantee` (ai9). **S4.**
      #
      # ## ⚠ A TABELA NÃO EXISTE NA ORIGEM DE PRODUÇÃO — DEC-103b
      #
      # `20220627125208_create_project_guarantees` está entre as **24 migrations
      # que nunca subiram**: a última aplicada em produção é de 25/05/2022 e o
      # sistema rodou em uso até 31/05/2025. Conferido no dump de 31/05/2025: a
      # relação **não existe**, exatamente como `project_guarantee_types`.
      # **Zero linha lida é o resultado esperado**, e o motor a reporta como
      # "tabela não existe nesta origem" — que é informação medida, diferente de
      # "conversor não escrito", que seria lacuna nossa.
      #
      # O conversor existe pelo mesmo motivo de `Converters::Charges`: se o
      # cliente rodar as migrations pendentes antes do cutover e cadastrar
      # garantias, a carga funciona sem ninguém escrever isto às pressas.
      #
      # ## `carrier_id` tem uma validação que NÃO existia no legado — BE-119
      #
      # `ProjectGuarantee#carrier_connected_to_project` exige que o portador
      # esteja **conectado ao projeto** (`ProjectToCarrierConnection`). O legado
      # só filtrava o `select` da tela; nada impedia um POST direto com portador
      # de outro projeto.
      #
      # Consequência para a carga, e é por isso que está escrito aqui:
      # `project_to_carrier_connections` **precisa estar carregada antes** — e
      # está, na ordem de `load_order.yml`. Garantia cujo par (projeto, portador)
      # não tenha conexão seria recusada linha a linha; `anomalies` a declara
      # antes, no dry-run, em vez de deixar a descoberta para a janela.
      #
      # ## `observation` era `string(255)` com textarea na tela
      #
      # DB: no ai9 é `text`. O campo da tela sempre foi um textarea, e 255
      # caracteres **cortavam observação de garantia em silêncio**. Aqui a coluna
      # cabe; o que já chegou cortado na origem não tem como voltar.
      #
      # ## `value` é `decimal(14,2)`, o padrão monetário desta migração
      #
      # Entra por `Values.to_decimal`, sem arredondamento extra (DEC-02). O model
      # exige `>= 0`; o legado exigia só presença.
      class ProjectGuarantees < Base
        def self.source_table = 'project_guarantees'
        def self.target_model = 'ProjectGuarantee'
        def self.requires = %w[ProjectGuarantee Project Carrier ProjectGuaranteeType]
        def self.owner_slice = 'S4'

        def self.references = {
          'project_id' => 'projects',
          'carrier_id' => 'carriers',
          'guarantee_type_id' => 'project_guarantee_types',
          'user_id' => 'livetat_auth_users'
        }

        def self.sums = %w[value]

        def convert(row)
          {
            project_id: ref('projects', row['project_id']),
            carrier_id: ref('carriers', row['carrier_id']),
            guarantee_type_id: ref('project_guarantee_types', row['guarantee_type_id']),
            user_id: ref('livetat_auth_users', row['user_id']),
            title: row['title'].to_s.strip,
            value: Values.to_decimal(row['value']),
            observation: row['observation'],
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        # BE-119 — a regra que o legado só tinha no `select` da tela. Sem a
        # conexão, o ai9 recusa a garantia; sem esta declaração, a recusa
        # apareceria no meio da carga em vez de no dry-run.
        def anomalies(row)
          projeto = row['project_id']
          portador = row['carrier_id']
          return [] if projeto.blank? || portador.blank?
          return [] if conexoes.include?([projeto.to_i, portador.to_i])

          [{ key: 'project_guarantees:carrier_not_connected',
             title: 'Garantia cujo portador NÃO está conectado ao projeto — o ai9 exige a conexão ' \
                    '(BE-119); o legado só filtrava o select da tela',
             line: "- pk=#{row['id']} projeto=#{projeto} portador=#{portador}" }]
        end

        private

        # Os pares (projeto, portador) que existem na ORIGEM, montados uma vez.
        # A conferência é contra a origem, não contra o destino: no dry-run o
        # destino ainda está vazio.
        def conexoes
          @conexoes ||= begin
            tabela = 'project_to_carrier_connections'
            if source.table?(tabela)
              source.ordered_rows(tabela)
                    .map { |r| [r['project_id'].to_i, r['carrier_id'].to_i] }
                    .to_set
            else
              Set.new
            end
          end
        end
      end
    end
  end
end

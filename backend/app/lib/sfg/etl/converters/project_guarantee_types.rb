# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `project_guarantee_types` (legado) -> `ProjectGuaranteeType` (ai9). **S4.**
      #
      # ## ⚠ A TABELA NÃO EXISTE NA ORIGEM DE PRODUÇÃO
      #
      # `20220627125208_create_project_guarantee_types` está entre as **24
      # migrations que nunca subiram**. Conferido no dump de 31/05/2025: a relação
      # não existe. Este conversor **vai ler zero linha** — e é o resultado
      # esperado, não uma falha. Mesma nota de `Converters::Charges`.
      #
      # ## E, mesmo se existisse, não haveria nada a migrar — DEC-86
      #
      # A decisão é explícita: *"não há nada a migrar — o conteúdo é novo"*. No
      # legado nenhum seed popula a tabela e o select de garantias
      # (`project_guarantees_controller.rb:52`) **sobe vazio** até alguém cadastrar
      # à mão. Os 8 tipos que existem hoje no ai9 são semeados por
      # `Seeds::Reference::ProjectGuaranteeTypes`, marcados `is_provisional`,
      # porque a lista definitiva é do cliente.
      #
      # ## Por que escrever assim mesmo
      #
      # 1. **DEC-102** — o conversor é escrito agora, com a regra na cabeça;
      # 2. se o cliente rodar as migrations pendentes antes do cutover e cadastrar
      #    tipos, a carga funciona sem ninguém lembrar de escrever isto às pressas;
      # 3. lacuna declarada é lacuna que alguém vê — o motor conta as linhas lidas,
      #    e "zero linha com o conversor declarado" é informação.
      #
      # ## `is_provisional` é marca do SEED, não do dado
      #
      # Linha vinda do legado é dado do cliente e entra **definitiva**. Carimbá-la
      # de provisória faria a tela avisar "esta lista é suposição" sobre exatamente
      # a lista que o cliente cadastrou. Os campos que o ai9 acrescentou e a origem
      # não tem (`sort_order`, `description`, `observation`) entram **vazios**,
      # nunca inventados.
      class ProjectGuaranteeTypes < Base
        def self.source_table = 'project_guarantee_types'
        def self.target_model = 'ProjectGuaranteeType'
        def self.owner_slice = 'S4'
        def self.references = { 'user_id' => 'livetat_auth_users' }
        def self.booleans = %w[is_active]
        # As duas são únicas NO BANCO no ai9 (DB-084); no legado, nenhuma.
        def self.uniques = [%w[title], %w[integration_key]]

        def convert(row)
          {
            title: row['title'].to_s.strip,
            integration_key: row['integration_key'],
            is_active: Values.to_boolean(row['is_active']).value,
            # DEC-86 — provisório é o que o SEED marca. O que veio do cliente não é.
            is_provisional: false,
            # Colunas que o ai9 acrescentou e a origem não tem. Zero e nulo são a
            # ausência honesta; qualquer outra coisa seria ordem inventada.
            sort_order: 0,
            user_id: ref('livetat_auth_users', row['user_id']),
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end
      end
    end
  end
end

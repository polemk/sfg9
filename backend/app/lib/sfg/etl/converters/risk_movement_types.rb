# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `risk_movement_types` (legado) -> `RiskMovementType` (ai9). **S5.**
      #
      # ### `credit_type` é o SINAL, e é a coluna crítica desta tabela
      #
      # `D` soma `+1` e `C` soma `−1` no recálculo do saldo. No ai9 há check
      # constraint no banco: qualquer valor fora de `('C','D')` **para a carga**,
      # em vez de virar movimento que não mexe no saldo, em silêncio, como no
      # legado (`parse_credit_type_value` devolvia 0).
      #
      # Por isso a coluna entra **normalizada e verificada**: espaço em branco e
      # caixa são tolerados (a origem não tem constraint nenhuma), qualquer outra
      # coisa é anomalia reportada.
      #
      # ### `credit_type_description` NÃO é carregada
      #
      # A coluna não existe no ai9 — virou derivada. No legado ela era gravada uma
      # vez, no create, e nunca recalculada: trocar o tipo de crédito na edição
      # deixava a descrição errada para sempre. Não há nada a preservar.
      #
      # ### As três chaves funcionais são contrato
      #
      # `liberacao_do_recurso`, `valor_transferido` e `transferencia_recebida` são
      # resolvidas por `integration_key` (B-09). Se a carga trouxer o tipo com
      # outra chave, `RiskMovementType.release` levanta erro de negócio na primeira
      # tentativa de lançar movimento — e é isso que `#post_load!` verifica **antes**
      # de a janela de cutover fechar.
      class RiskMovementTypes < Base
        VALID_CREDIT_TYPES = %w[C D].freeze

        def self.source_table = 'risk_movement_types'
        def self.target_model = 'RiskMovementType'
        def self.owner_slice = 'S5'
        def self.references = { 'user_id' => 'livetat_auth_users' }
        def self.booleans = %w[is_active is_default is_system_exclusive is_transfer]
        def self.uniques = [%w[title], %w[integration_key]]

        def convert(row)
          {
            title: row['title'],
            integration_key: row['integration_key'].presence || GlobalCatalog.slugify(row['title']),
            credit_type: normalize_credit_type(row['credit_type']),
            is_active: Values.to_boolean(row['is_active']).value,
            is_default: Values.to_boolean(row['is_default']).value,
            is_system_exclusive: Values.to_boolean(row['is_system_exclusive']).value,
            is_transfer: Values.to_boolean(row['is_transfer']).value,
            user_id: ref('livetat_auth_users', row['user_id']),
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        # Espaço e caixa são ruído da origem (que não tem constraint); qualquer
        # outra coisa é dado que mudaria saldo em silêncio, e a carga tem de parar.
        def normalize_credit_type(valor)
          normalizado = valor.to_s.strip.upcase
          return normalizado if VALID_CREDIT_TYPES.include?(normalizado)

          raise ArgumentError,
                "credit_type inválido na origem: #{valor.inspect}. " \
                "Só 'C' e 'D' têm sinal definido — qualquer outro valor faria o movimento " \
                'não mexer no saldo, sem erro nenhum (é o defeito do legado).'
        end

        # As três chaves funcionais existem depois da carga? Sem elas a S7 não
        # lança um único movimento.
        def self.post_load!
          return { missing: [] } unless model_ready?('RiskMovementType')

          faltando = [
            ::RiskMovementType::RELEASE_KEY,
            ::RiskMovementType::TRANSFER_OUT_KEY,
            ::RiskMovementType::TRANSFER_IN_KEY
          ].reject { |chave| ::RiskMovementType.exists?(integration_key: chave) }

          { missing: faltando }
        end
      end
    end
  end
end

# frozen_string_literal: true

module Contracts
  # S12 / tarefas 6.3 e 6.4 — **a carga dos contratos e dos aceites do legado**.
  #
  # Duas regras vindas de decisão, não de gosto:
  #
  # **DB-330 / 6.3 — a `version` do legado é congelada como está.** A numeração
  # existente vira a numeração daqui, sem renumerar. Renumerar quebraria a
  # correspondência com qualquer prova de aceite anterior, que é justamente o
  # que esta fatia existe para não perder. O dry-run reporta **autores órfãos**
  # (`creator_id` apontando para usuário que não veio) — a FK é `ON DELETE SET
  # NULL` e o contrato entra sem autor em vez de não entrar.
  #
  # **DEC-66 / 6.4 — todo aceite existente entra marcado `implicit_legacy`,
  # preservando a data original.** Não é escolha desta rotina: o passivo do
  # legado tem duas origens conhecidas — o `after_create` que gravava aceite sem
  # interação (`user_decorator.rb:234-240`) e o seed que fabricou aceite
  # retroativo para toda a base (`db/seeds.rb:141-157`). A base antiga **não
  # distingue quem aceitou de quem foi carimbado**, então nada aqui pode dizer
  # que distingue. `implicit_legacy` **não satisfaz a pendência**: o novo aceite
  # explícito é exigido na próxima entrada, e é o banner que o pede.
  module LegacyImport
    Report = Struct.new(:contracts_created, :contracts_updated, :orphan_creators,
                        :deals_created, :deals_skipped, :errors, keyword_init: true) do
      def to_h
        { contracts_created: contracts_created, contracts_updated: contracts_updated,
          orphan_creators: orphan_creators, deals_created: deals_created,
          deals_skipped: deals_skipped, errors: errors }
      end
    end

    module_function

    # `contract_rows`: `{ legacy_id:, kind:, version:, title:, body:,
    #                     creator_legacy_id:, created_at: }`
    # `deal_rows`:     `{ legacy_id:, contract_legacy_id:, user_legacy_id:, created_at: }`
    def call(contract_rows: [], deal_rows: [], dry_run: true)
      relatorio = Report.new(contracts_created: 0, contracts_updated: 0, orphan_creators: 0,
                             deals_created: 0, deals_skipped: 0, errors: [])

      Array(contract_rows).each { |row| import_contract(normalize(row), relatorio, dry_run) }
      Array(deal_rows).each { |row| import_deal(normalize(row), relatorio, dry_run) }

      relatorio
    end

    def normalize(row)
      row.respond_to?(:symbolize_keys) ? row.symbolize_keys : row
    end

    def import_contract(row, relatorio, dry_run)
      kind = Contract.kind_for(row[:kind])
      if kind.blank?
        # OPS-332: documento de origem sem tipo do catálogo é **ignorado e
        # registrado**, nunca carregado às cegas.
        relatorio.errors << "contrato legado #{row[:legacy_id]}: tipo `#{row[:kind]}` fora do catálogo — ignorado"
        return
      end

      autor = User.find_by(legacy_id: row[:creator_legacy_id])
      relatorio.orphan_creators += 1 if row[:creator_legacy_id].present? && autor.nil?

      return relatorio.contracts_created += 1 if dry_run && Contract.find_by(legacy_id: row[:legacy_id]).nil?
      return relatorio.contracts_updated += 1 if dry_run

      contrato = Contract.find_or_initialize_by(legacy_id: row[:legacy_id])
      novo = contrato.new_record?
      # `version` congelada: atribuída explicitamente, então o
      # `assign_version_and_slug` do model não calcula nada.
      contrato.assign_attributes(kind: kind, version: row[:version], title: row[:title],
                                 creator_id: autor&.id,
                                 published_at: row[:created_at] || Time.current)
      contrato.description = row[:body] if row[:body].present?

      if contrato.save
        novo ? relatorio.contracts_created += 1 : relatorio.contracts_updated += 1
      else
        relatorio.errors << "contrato legado #{row[:legacy_id]}: #{contrato.errors.full_messages.to_sentence}"
      end
    end

    def import_deal(row, relatorio, dry_run)
      contrato = Contract.find_by(legacy_id: row[:contract_legacy_id]) unless dry_run
      usuario = User.find_by(legacy_id: row[:user_legacy_id]) unless dry_run

      if dry_run
        relatorio.deals_created += 1
        return
      end

      if contrato.nil? || usuario.nil?
        relatorio.deals_skipped += 1
        relatorio.errors << "aceite legado #{row[:legacy_id]}: contrato ou usuário não encontrado"
        return
      end

      data = row[:created_at] || Time.current
      deal = ContractDeal.find_or_initialize_by(user_id: usuario.id, contract_id: contrato.id)
      deal.assign_attributes(
        legacy_id: row[:legacy_id],
        # DEC-66, o ponto inteiro desta rotina.
        source: ContractDeal::SOURCE_IMPLICIT_LEGACY,
        accepted_at: data,
        legacy_accepted_at: data,
        contract_kind: contrato.kind,
        contract_version: contrato.version
        # Sem IP, sem user-agent e **sem hash**: não havia requisição, e inventar
        # o hash do texto atual faria um aceite carimbado parecer prova de
        # leitura. O vazio aqui é informação.
      )

      if deal.save
        relatorio.deals_created += 1
      else
        relatorio.deals_skipped += 1
        relatorio.errors << "aceite legado #{row[:legacy_id]}: #{deal.errors.full_messages.to_sentence}"
      end
    end
  end
end

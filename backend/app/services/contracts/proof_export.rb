# frozen_string_literal: true

# `csv` deixou de ser gem padrão no Ruby 3.4 e não é carregada por tabela.
require 'csv'

module Contracts
  # S12 / OPS-333 — **o exportador de prova** exigido pela DEC-80.
  #
  # Uma linha por aceite, com tudo o que a prova precisa: quem, qual versão,
  # quando, de onde, com que navegador, o **hash** do texto e o **texto
  # integral** que a pessoa leu.
  #
  # Por que o texto vai junto e não só o hash: a DEC-80 recusou o versionamento
  # imutável (opção (d)), então o documento continua editável no lugar. O hash
  # prova *que* mudou; só o corpo gravado prova *o que* foi lido. Sem ele, um
  # contrato editado depois de 400 aceites vira 400 provas que dizem "não é este
  # texto" e nada mais.
  module ProofExport
    HEADERS = [
      'ID do aceite', 'Usuário', 'E-mail', 'Tipo de contrato', 'Versão',
      'Origem do aceite', 'Aceito em', 'Aceite legado em', 'IP', 'User-Agent',
      'Hash do texto', 'Confere com o texto atual', 'Texto aceito'
    ].freeze

    ORIGINS = {
      ContractDeal::SOURCE_EXPLICIT => 'Explícito (o usuário clicou)',
      ContractDeal::SOURCE_IMPLICIT_LEGACY => 'Implícito (carimbado pela base legada)'
    }.freeze

    module_function

    # `scope` permite exportar tudo, um contrato, ou um usuário — a mesma
    # rotina, porque a prova é a mesma.
    def rows(scope = ContractDeal.all)
      scope.includes(:user, :contract).order(accepted_at: :desc).map { |deal| row_for(deal) }
    end

    def row_for(deal)
      [
        deal.id,
        deal.user&.name,
        deal.user&.email,
        deal.contract_kind,
        deal.contract_version,
        ORIGINS.fetch(deal.source, deal.source),
        deal.accepted_at&.iso8601,
        deal.legacy_accepted_at&.iso8601,
        deal.ip_address,
        deal.user_agent,
        deal.content_hash,
        deal.hash_matches_current? ? 'sim' : 'não',
        Renderer.text(deal.accepted_body)
      ]
    end

    def to_csv(scope = ContractDeal.all)
      CSV.generate(force_quotes: true) do |csv|
        csv << HEADERS
        rows(scope).each { |r| csv << r }
      end
    end
  end
end

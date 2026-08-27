# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `projects` (legado) -> `Project` (ai9).
      #
      # Duas renomeações que o motor NÃO adivinha e que por isso estão escritas aqui,
      # no único lugar que conhece as duas pontas: `formal` -> `name` e `smart_id` ->
      # `slug`. Traduzir campo em coluna é a responsabilidade nº 2 do escritor.
      #
      # `responsible_formal` -> `responsible_name` carrega junto o **BE-452 (c)**: no
      # ETL de 2021 o responsável caía em cascata até um e-mail de pessoa real
      # embutido no código-fonte e, por fim, ao primeiro usuário. Esse dado está em
      # produção e o dry-run conta quantos projetos estão nessa condição — nenhum dado
      # pessoal fica embutido no código do ai9.
      class Projects < Base
        def self.source_table = 'projects'
        def self.target_model = 'Project'
        def self.owner_slice = 'S4'
        def self.references = { 'user_id' => 'livetat_auth_users', 'segment_id' => 'segments' }
        def self.booleans = %w[is_active]
        def self.uniques = [%w[smart_id]]

        def convert(row)
          {
            name: row['formal'],
            slug: Values.to_smart_id(row['smart_id']),
            integration_key: row['integration_key'],
            user_id: ref('livetat_auth_users', row['user_id']),
            segment_id: ref('segments', row['segment_id']),
            is_active: Values.to_boolean(row['is_active']).value,
            color: row['color'],
            address_type: row['address_type'],
            address: row['address'],
            address_number: row['address_number'],
            address_complement: row['address_complement'],
            neighborhood: row['neighborhood'],
            cep: self.class.usable_cep(row['cep']),
            address_state: row['address_state'],
            address_city: row['address_city'],
            closing_date: row['closing_date'],
            importing_id: row['importing_id'],
            responsible_email: row['responsible_email'],
            responsible_name: row['responsible_formal'],
            responsible_id: ref('livetat_auth_users', row['responsible_id']),
            job_state: row['job_state'],
            job_report: row['job_report'],
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        # D-PAR-01. O legado nao validava CEP; o `Project` do ai9 valida
        # (`/\A\d{5}-?\d{3}\z/`, `project.rb:95`) e o escritor chama `save!`. Um CEP
        # de 7 digitos derrubava a CARGA INTEIRA com `ActiveRecord::RecordInvalid`
        # nao tratado — sem relatorio, sem linha de anomalia, no meio do lote.
        # Medido no dump de 31/05/2025: 3 projetos de 83 com 7 digitos.
        # O endereco NAO e chave de nada: o CEP invalido entra VAZIO e sai listado
        # como anomalia, em vez de barrar a virada.
        def self.usable_cep(value)
          digits = value.to_s.gsub(/\D/, '')
          digits.length == 8 ? value : nil
        end

        def anomalies(row)
          out = []

          unless row['cep'].to_s.strip.empty? || self.class.usable_cep(row['cep'])
            out << { key: 'projects:cep_invalido',
                     title: 'D-PAR-01 — CEP do legado fora de 8 digitos: entra VAZIO (o legado nao validava; o ai9 valida)',
                     # DEC-128.1 manda LISTAR "com o valor de origem": sem ele a
                     # linha diz que ha um CEP errado e nao diz qual, e quem for
                     # corrigir tem de voltar ao dump para descobrir.
                     line: "- pk=#{row['id']} digitos=#{row['cep'].to_s.gsub(/\D/, '').length} " \
                           "(origem: #{row['cep'].inspect})" }
          end

          return out if row['responsible_email'].to_s.strip.empty?

          # BE-452 (c) / BE-454: a terceira correcao pos-importacao SOBRESCREVIA o
          # responsavel definido pela segunda, e a ordem nao estava documentada.
          out << { key: 'projects:responsible_from_2021_fallback',
                   title: 'BE-452/BE-454 — responsavel de projeto definido pelo fallback do ETL de 2021. Conferencia humana do responsavel correto',
                   line: "- pk=#{row['id']} `#{row['formal']}` responsavel=`#{row['responsible_email']}`" }
          out
        end
      end
    end
  end
end

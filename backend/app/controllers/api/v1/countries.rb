# frozen_string_literal: true

module Api
  module V1
    class Countries < Grape::API
      format :json

      resource :countries do
        desc 'Lista países com DDI e ISO, com busca parcial'
        params do
          optional :q, type: String
        end
        get do
          data = COUNTRIES
          q = (params[:q] || '').to_s.strip.downcase
          if q.present?
            data = data.select do |c|
              c[:name].downcase.include?(q) || c[:iso2].downcase.include?(q) || c[:dial_code].start_with?(q.gsub('+',
                                                                                                                 ''))
            end
          end
          { countries: data }
        end

        # S2 / BE-413 — as **opções encadeadas** do formulário de endereço.
        #
        # No legado as actions `state_select` e `city_select` existiam no
        # controller e **não tinham rota**: o formulário chamava um caminho que
        # o roteador não conhecia, e o select de estado ficava vazio para
        # sempre. Aqui a rota existe, e a lista é servida pelo servidor para que
        # a sigla gravada seja a mesma que o servidor valida.
        desc 'Estados (subdivisões) de um país' do
          summary 'Estados por país'
          detail 'Hoje só o Brasil tem lista. Outro país devolve lista vazia — nunca 404, porque "país sem subdivisão cadastrada" não é erro.'
        end
        params do
          requires :code, type: String, desc: 'ISO-2 do país (ex.: BR)'
        end
        get ':code/states' do
          { states: SUBDIVISIONS.fetch(params[:code].to_s.upcase, []) }
        end
      end

      # As 27 unidades federativas. Tabela, não consulta: é dado que não muda,
      # e uma tabela de banco para isto seria uma migration a mais e uma
      # consulta por formulário aberto.
      BRAZILIAN_STATES = [
        %w[AC Acre], %w[AL Alagoas], %w[AP Amapá], %w[AM Amazonas], %w[BA Bahia],
        %w[CE Ceará], ['DF', 'Distrito Federal'], ['ES', 'Espírito Santo'], %w[GO Goiás],
        ['MA', 'Maranhão'], ['MT', 'Mato Grosso'], ['MS', 'Mato Grosso do Sul'],
        ['MG', 'Minas Gerais'], %w[PA Pará], ['PB', 'Paraíba'], ['PR', 'Paraná'],
        ['PE', 'Pernambuco'], ['PI', 'Piauí'], ['RJ', 'Rio de Janeiro'],
        ['RN', 'Rio Grande do Norte'], ['RS', 'Rio Grande do Sul'], ['RO', 'Rondônia'],
        %w[RR Roraima], ['SC', 'Santa Catarina'], ['SP', 'São Paulo'], %w[SE Sergipe],
        ['TO', 'Tocantins']
      ].map { |code, name| { code: code, name: name } }.freeze

      SUBDIVISIONS = { 'BR' => BRAZILIAN_STATES }.freeze

      COUNTRIES = [
        { name: 'Brazil', iso2: 'BR', dial_code: '55' },
        { name: 'Argentina', iso2: 'AR', dial_code: '54' },
        { name: 'United States', iso2: 'US', dial_code: '1' },
        { name: 'Canada', iso2: 'CA', dial_code: '1' },
        { name: 'Mexico', iso2: 'MX', dial_code: '52' },
        { name: 'United Kingdom', iso2: 'GB', dial_code: '44' },
        { name: 'Germany', iso2: 'DE', dial_code: '49' },
        { name: 'France', iso2: 'FR', dial_code: '33' },
        { name: 'Spain', iso2: 'ES', dial_code: '34' },
        { name: 'Portugal', iso2: 'PT', dial_code: '351' },
        { name: 'Italy', iso2: 'IT', dial_code: '39' },
        { name: 'Netherlands', iso2: 'NL', dial_code: '31' },
        { name: 'Belgium', iso2: 'BE', dial_code: '32' },
        { name: 'Switzerland', iso2: 'CH', dial_code: '41' },
        { name: 'Austria', iso2: 'AT', dial_code: '43' },
        { name: 'Ireland', iso2: 'IE', dial_code: '353' },
        { name: 'Sweden', iso2: 'SE', dial_code: '46' },
        { name: 'Norway', iso2: 'NO', dial_code: '47' },
        { name: 'Denmark', iso2: 'DK', dial_code: '45' },
        { name: 'Finland', iso2: 'FI', dial_code: '358' },
        { name: 'Poland', iso2: 'PL', dial_code: '48' },
        { name: 'Czech Republic', iso2: 'CZ', dial_code: '420' },
        { name: 'Russia', iso2: 'RU', dial_code: '7' },
        { name: 'China', iso2: 'CN', dial_code: '86' },
        { name: 'Japan', iso2: 'JP', dial_code: '81' },
        { name: 'South Korea', iso2: 'KR', dial_code: '82' },
        { name: 'India', iso2: 'IN', dial_code: '91' },
        { name: 'Australia', iso2: 'AU', dial_code: '61' },
        { name: 'New Zealand', iso2: 'NZ', dial_code: '64' },
        { name: 'South Africa', iso2: 'ZA', dial_code: '27' },
        { name: 'Colombia', iso2: 'CO', dial_code: '57' },
        { name: 'Chile', iso2: 'CL', dial_code: '56' },
        { name: 'Peru', iso2: 'PE', dial_code: '51' },
        { name: 'Paraguay', iso2: 'PY', dial_code: '595' },
        { name: 'Uruguay', iso2: 'UY', dial_code: '598' },
        { name: 'Bolivia', iso2: 'BO', dial_code: '591' },
        { name: 'Ecuador', iso2: 'EC', dial_code: '593' },
        { name: 'Venezuela', iso2: 'VE', dial_code: '58' },
        { name: 'Guatemala', iso2: 'GT', dial_code: '502' },
        { name: 'Honduras', iso2: 'HN', dial_code: '504' },
        { name: 'El Salvador', iso2: 'SV', dial_code: '503' },
        { name: 'Costa Rica', iso2: 'CR', dial_code: '506' },
        { name: 'Panama', iso2: 'PA', dial_code: '507' },
        { name: 'Dominican Republic', iso2: 'DO', dial_code: '1' },
        { name: 'Puerto Rico', iso2: 'PR', dial_code: '1' }
      ].freeze
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    # S3 / OPS-057 (Lacuna **L-11**) — as **unidades federativas do Brasil**,
    # como CADASTRO e não como geocodificação.
    #
    # No legado, cidade e UF do portador saíam do `geocoder` + `city-state`: um
    # serviço externo, com **timeout de ~3h20** e **sem cache**, consultado para
    # preencher dois campos de formulário. Cidade e UF de uma contraparte
    # financiadora são dado de cadastro — quem digita sabe onde a sede fica.
    # **`geocoder` e `city-state` não são portados** (a geolocalização inteira é
    # descartada pelo DEC-92).
    #
    # A forma é a de `api/v1/countries.rb`: constante no próprio arquivo, não
    # tabela. É dado que não muda, e uma tabela seria uma migration a mais e uma
    # consulta por formulário aberto.
    #
    # **A lista é a MESMA de `Countries::BRAZILIAN_STATES`**, e é dela que sai —
    # duas listas de 27 UFs divergem na primeira correção de acento. Este
    # endpoint existe porque o formulário do portador pede "as UFs", não "as
    # subdivisões do país BR": o caminho `/api/v1/br_states` diz o que devolve.
    class BrStates < Grape::API
      format :json

      # Só as siglas — é o que o model do portador valida (`Carrier#uf`).
      CODES = Countries::BRAZILIAN_STATES.map { |uf| uf[:code] }.freeze

      # `{ code:, name: }`, a mesma forma que o `Select` do front consome.
      UF = Countries::BRAZILIAN_STATES

      resource :br_states do
        desc 'Unidades federativas do Brasil' do
          summary 'UFs'
          detail 'Cadastro, não geocodificação (OPS-057 / L-11). Aceita `q` para filtrar por sigla ou nome.'
        end
        params do
          optional :q, type: String, desc: 'Filtro parcial por sigla ou nome'
        end
        get do
          termo = I18n.transliterate(params[:q].to_s.strip).downcase

          dados =
            if termo.blank?
              UF
            else
              casaram = UF.select do |uf|
                uf[:code].downcase.include?(termo) ||
                  I18n.transliterate(uf[:name]).downcase.include?(termo)
              end
              # **A sigla exata vem primeiro.** Digitar "sp" também casa com
              # "E-sp-írito Santo", e devolver o ES antes do SP faz o usuário
              # achar que o campo está quebrado. Ordenar em vez de excluir
              # preserva a busca por nome, que é o caso de quem não sabe a sigla.
              casaram.sort_by { |uf| uf[:code].downcase == termo ? 0 : 1 }
            end

          { states: dados }
        end
      end
    end
  end
end

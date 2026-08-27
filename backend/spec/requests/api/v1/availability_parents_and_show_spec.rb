# frozen_string_literal: true

require 'rails_helper'

# **BE-111, BE-133, BE-141 — os pais válidos e o detalhe do padrão.**
#
# Os três chegaram à Phase 4 pelo mesmo motivo: `grep -rn available_parents
# spec/` e `grep -rn availability_templates/:id spec/` não achavam nada. O
# código conferia com o legado; ninguém tinha provado.
#
# ## O que "pai válido" significa, e por que ele erra em silêncio
#
# A hierarquia tem **3 níveis** (`AvailabilityTemplate::MAX_LEVEL`). Um padrão
# de 3º nível não pode ser pai de ninguém, então ele nunca aparece no "Faz parte
# de". Um erro aqui não quebra nada na hora: oferece um pai impossível, o
# usuário escolhe, e a **gravação** é que recusa — com uma mensagem sobre nível
# que não tem relação com o que ele acabou de fazer.
#
# ## BE-133 — o detalhe, e o defeito do legado que ele conserta
#
# No legado a view do detalhe chamava `.projects`, uma associação **que não
# existe**: abrir o detalhe levantava `NoMethodError`. Aqui o endpoint responde
# para os dois tipos de padrão — global e de projeto —, e é isso que se exige.
RSpec.describe 'Api::V1 — pais válidos e detalhe do padrão', type: :request do
  before { UserType.seed_default_types! }

  let(:og) { create(:user, :og) }
  let!(:projeto) { create_project_with_owner(og, slug: 'disp-par', name: 'Pais') }
  let(:headers) { auth_headers(og, project: projeto) }

  def json = JSON.parse(response.body)

  # ------------------------------------------------------------------ global
  describe 'BE-111 — pais válidos do catálogo global' do
    let!(:n1) { create(:global_availability_template, title: 'Nível 1') }
    let!(:n2) { create(:global_availability_template, title: 'Nível 2', parent_template: n1) }
    let!(:n3) { create(:global_availability_template, title: 'Nível 3', parent_template: n2) }

    it 'o padrão de 3º nível NUNCA aparece — ele não pode ter filho' do
      get '/api/v1/availability_templates/available_parents', headers: headers

      expect(response).to have_http_status(:ok)
      titulos = json.map { |t| t['title'] }
      expect(titulos).to include('Nível 1', 'Nível 2')
      expect(titulos).not_to include('Nível 3')
    end

    it 'pedindo pai para o 2º nível, só o 1º serve' do
      get '/api/v1/availability_templates/available_parents?level=2', headers: headers

      expect(response).to have_http_status(:ok)
      expect(json.map { |t| t['title'] }).to eq(['Nível 1'])
    end

    it 'pedindo pai para o 1º nível, a lista é vazia — raiz não tem pai' do
      get '/api/v1/availability_templates/available_parents?level=1', headers: headers

      expect(response).to have_http_status(:ok)
      expect(json).to be_empty
    end

    it 'nível fora de 1..3 é recusado pelo servidor, e não devolve lista errada' do
      get '/api/v1/availability_templates/available_parents?level=9', headers: headers

      expect(response).to have_http_status(:bad_request)
    end
  end

  # ----------------------------------------------------------------- projeto
  describe 'BE-141 — pais válidos do projeto' do
    let!(:meu_n1) { create(:project_availability_template, project: projeto, title: 'Meu nível 1') }
    let!(:meu_n2) do
      create(:project_availability_template, project: projeto, title: 'Meu nível 2', parent_template: meu_n1)
    end
    let!(:meu_n3) do
      create(:project_availability_template, project: projeto, title: 'Meu nível 3', parent_template: meu_n2)
    end

    # O defeito que o legado tinha aqui era de VAZAMENTO, não de nível: ele
    # embutia `AvailabilityTemplate.all` num atributo `data-templates` do HTML e
    # filtrava no cliente. O padrão de outro projeto ia junto, no fonte da
    # página, para qualquer um que abrisse o formulário.
    it 'NENHUM padrão de outro projeto entra na lista' do
      outro = create(:project)
      create(:project_availability_template, project: outro, title: 'Padrão alheio')

      get '/api/v1/project_availabilities/available_parents', headers: headers

      expect(response).to have_http_status(:ok)
      titulos = json.map { |t| t['title'] }
      expect(titulos).to include('Meu nível 1', 'Meu nível 2')
      expect(titulos).not_to include('Padrão alheio')
    end

    it 'o 3º nível também não aparece aqui' do
      get '/api/v1/project_availabilities/available_parents', headers: headers

      expect(json.map { |t| t['title'] }).not_to include('Meu nível 3')
    end
  end

  # ------------------------------------------------------------------ detalhe
  describe 'BE-133 — detalhe do padrão' do
    it 'responde para o padrão GLOBAL' do
      global = create(:global_availability_template, title: 'Caixa geral')

      get "/api/v1/availability_templates/#{global.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json['id']).to eq(global.id)
      expect(json['title']).to eq('Caixa geral')
    end

    # É este o caso que o legado quebrava: a view chamava `.projects`, associação
    # inexistente, e o detalhe levantava `NoMethodError`.
    it 'responde TAMBÉM para o padrão de PROJETO — era aqui que o legado estourava' do
      do_projeto = create(:project_availability_template, project: projeto, title: 'Caixa do projeto')

      get "/api/v1/availability_templates/#{do_projeto.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json['id']).to eq(do_projeto.id)
      expect(json['title']).to eq('Caixa do projeto')
    end

    it 'id inexistente é 404, e id que não é UUID também — sem estourar' do
      get "/api/v1/availability_templates/#{SecureRandom.uuid}", headers: headers
      expect(response).to have_http_status(:not_found)

      get '/api/v1/availability_templates/nao-e-uuid', headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end

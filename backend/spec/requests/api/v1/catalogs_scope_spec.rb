# frozen_string_literal: true

require 'rails_helper'

# S3 / tarefas 4.2.1 e 4.2.2 — **o contrato C1 num catálogo GLOBAL**.
#
# Aqui a regra é a OPOSTA da das fatias S4 e S11, e é opostas de propósito:
# catálogo global **não recebe escopo de projeto** (`§0.6`, regra 4). O menu
# esconde a tela de administração do catálogo; o dado do catálogo é de todos os
# autenticados (DEC-18.4).
#
# Este arquivo existe para reprovar quem vier "consertar" o catálogo aplicando
# `for_project` nele — um portador que sumisse da tela do projeto B quebraria o
# `risk_control` que já aponta para ele.
RSpec.describe 'Escopo dos catálogos globais (contrato C1, regra 4)', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:og) { create(:user, :og) }
  let(:sem_projeto) { create(:user, :colaborador) }

  CAMINHOS = %w[
    /api/v1/carriers
    /api/v1/carrier_groups
    /api/v1/segments
    /api/v1/sub_segments
    /api/v1/project_guarantee_types
  ].freeze

  # 4.2.1 — sem projeto corrente, a leitura funciona.
  it 'usuário SEM projeto corrente lê os cinco catálogos' do
    create(:carrier)
    create(:carrier_group)
    create(:segment)
    create(:sub_segment)
    create(:project_guarantee_type)

    expect(sem_projeto.current_project_id).to be_nil

    CAMINHOS.each do |path|
      get path, headers: auth_headers(sem_projeto)
      expect(response).to have_http_status(:ok), "#{path} exigiu projeto corrente"
      expect(JSON.parse(response.body).size).to eq(1), "#{path} devolveu conjunto vazio para quem não tem projeto"
    end
  end

  # O mesmo dado, visto de dois projetos diferentes. É a metade que o teste de
  # "sem projeto" não cobre: o catálogo não pode ser filtrado POR projeto.
  it 'o mesmo portador aparece para membros de projetos DIFERENTES' do
    portador = create(:carrier, title: 'Contraparte Compartilhada')

    a = create(:user, :gerente)
    b = create(:user, :gerente)
    projeto_a = create_project_with_owner(a, slug: 'proj-a')
    projeto_b = create_project_with_owner(b, slug: 'proj-b')

    [[a, projeto_a], [b, projeto_b]].each do |usuario, projeto|
      get '/api/v1/carriers', headers: auth_headers(usuario, project: projeto)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).map { |c| c['id'] }).to include(portador.id)
    end
  end

  # Nenhum endpoint desta fatia pode chamar `current_project!`. A leitura é do
  # CÓDIGO porque um teste de comportamento passaria mesmo com a chamada
  # presente enquanto o usuário do teste tivesse projeto.
  it 'nenhum endpoint da fatia chama `current_project!`' do
    arquivos = %w[carriers carrier_groups segments sub_segments project_guarantee_types br_states catalog_helpers]
                 .map { |n| Rails.root.join("app/controllers/api/v1/#{n}.rb") }

    infratores = arquivos.select do |arquivo|
      # A menção em comentário é justamente onde a decisão está escrita; o que
      # não pode é a CHAMADA.
      File.readlines(arquivo).any? { |linha| linha.match?(/^\s*[^#]*current_project!/) }
    end

    expect(infratores).to be_empty,
                          "catálogo global não recebe escopo de projeto (C1, regra 4): #{infratores.join(', ')}"
  end

  it 'nenhum model da fatia é `project_scoped?`, e todos são `global_catalog?`' do
    [Carrier, CarrierGroup, Segment, SubSegment, ProjectGuaranteeType].each do |model|
      expect(model).to be_global_catalog
      expect(model.respond_to?(:project_scoped?)).to be(false), "#{model} virou escopado por projeto"
      expect(model.column_names).not_to include('project_id'), "#{model} ganhou `project_id`"
    end
  end

  # 4.2.2 — id que chega por parâmetro entra no `where`, não desliga o filtro.
  #
  # É o inverso exato da família D-01/D-16/D-29/D-76/D-100 do legado, em que a
  # chegada de um id por parâmetro fazia o filtro sumir.
  describe 'filtro por `group_id` em `carriers`' do
    it 'filtra DENTRO do conjunto, e um `group_id` inexistente devolve VAZIO' do
      grupo = create(:carrier_group)
      create(:carrier, group: grupo)
      create(:carrier) # fora do grupo

      get '/api/v1/carriers', params: { group_id: grupo.id }, headers: auth_headers(og)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(1)
      expect(response.headers['X-Total-Count']).to eq('1')

      get '/api/v1/carriers', params: { group_id: SecureRandom.uuid }, headers: auth_headers(og)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to be_empty
      expect(response.headers['X-Total-Count']).to eq('0')
    end
  end
end

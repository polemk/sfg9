# frozen_string_literal: true

require 'rails_helper'

# S3 / BE-075..BE-078 — segmentos e subsegmentos.
RSpec.describe 'Segmentos e subsegmentos', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:og) { create(:user, :og) }

  # 4.3.1 — **o D-21 literal**. No legado `Segment` validava `user_id` presente
  # e `segment_params` não o permitia: a criação falhava 100% das vezes, em
  # produção, desde 2021.
  describe 'POST /api/v1/segments (D-21)' do
    it 'FUNCIONA sem `user_id` no payload, e o autor gravado é o da SESSÃO' do
      post '/api/v1/segments', params: { title: 'Construção Civil' }, headers: auth_headers(og)

      expect(response).to have_http_status(:created)
      segmento = Segment.find(JSON.parse(response.body)['id'])
      expect(segmento.user_id).to eq(og.id)
      expect(segmento.integration_key).to eq('construcao_civil')
    end

    it 'IGNORA o `user_id` que vier do corpo' do
      intruso = create(:user, :admin)
      post '/api/v1/segments', params: { title: 'Agro', user_id: intruso.id }, headers: auth_headers(og)

      expect(response).to have_http_status(:created)
      expect(Segment.find(JSON.parse(response.body)['id']).user_id).to eq(og.id)
    end

    it 'título repetido → 422 (DB-064: único no banco, fecha o caminho do D-26)' do
      create(:segment, title: 'Varejo')
      post '/api/v1/segments', params: { title: 'Varejo' }, headers: auth_headers(og)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # BE-075 — ordenação por título **e** por chave.
  describe 'ordenação de segmentos' do
    it 'ordena por título e por chave' do
      create(:segment, title: 'Zeta Comércio')
      create(:segment, title: 'Alfa Indústria')

      get '/api/v1/segments', params: { ordering_keys: ['title'] }, headers: auth_headers(og)
      expect(JSON.parse(response.body).map { |s| s['title'] }).to eq(['Alfa Indústria', 'Zeta Comércio'])

      get '/api/v1/segments', params: { ordering_keys: ['key'], ordering_style: ['down'] },
                              headers: auth_headers(og)
      expect(JSON.parse(response.body).map { |s| s['integration_key'] }).to eq(%w[zeta_comercio alfa_industria])
    end
  end

  # BE-077 — a ordenação do subsegmento é resolvida por ELE, não por `Segment`.
  it 'a allowlist de ordenação de subsegmento é INDEPENDENTE da de segmento (BE-077)' do
    expect(SubSegment::ORDERING).not_to equal(Segment::ORDERING)
    expect(SubSegment.reflect_on_all_associations.map(&:klass)).not_to include(Segment)
    expect(SubSegment.column_names).not_to include('segment_id') # DC-13
  end

  # 4.3.5 / BE-078 / D-24 — exclusão bloqueada por projeto vinculado.
  describe 'DELETE bloqueado por projeto vinculado' do
    it 'segmento em uso por projeto → 422 e o projeto CONTINUA apontando' do
      segmento = create(:segment)
      projeto = create_project_with_owner(og, slug: 'com-segmento')
      projeto.update!(segment_id: segmento.id)

      delete "/api/v1/segments/#{segmento.id}", headers: auth_headers(og)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to include('projeto')
      expect(Segment.exists?(segmento.id)).to be(true)
      expect(projeto.reload.segment_id).to eq(segmento.id)
    end

    it 'subsegmento em uso por projeto → 422' do
      sub = create(:sub_segment)
      projeto = create_project_with_owner(og, slug: 'com-subsegmento')
      projeto.update!(sub_segment_id: sub.id)

      delete "/api/v1/sub_segments/#{sub.id}", headers: auth_headers(og)

      expect(response).to have_http_status(:unprocessable_content)
      expect(SubSegment.exists?(sub.id)).to be(true)
    end

    it 'segmento sem projeto é excluído' do
      segmento = create(:segment)
      delete "/api/v1/segments/#{segmento.id}", headers: auth_headers(og)
      expect(response).to have_http_status(:ok)
    end
  end

  it 'a listagem informa quantos projetos usam cada segmento (o número que explica o 422)' do
    segmento = create(:segment)
    projeto = create_project_with_owner(og, slug: 'conta')
    projeto.update!(segment_id: segmento.id)

    get '/api/v1/segments', headers: auth_headers(og)
    expect(JSON.parse(response.body).first['projects_count']).to eq(1)
  end
end

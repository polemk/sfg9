# frozen_string_literal: true

require 'rails_helper'

# S3 / BE-072, BE-073, BE-074 — grupos de portadores.
RSpec.describe 'Grupos de portadores', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:og) { create(:user, :og) }

  # 4.3.2 — no legado ordenar por "Grupo" respondia **500**: o controller
  # chamava `CarrierGroup.prepare_ordering`, que o model nunca definiu (D-21).
  describe 'ordenação (D-21)' do
    it 'ordenar por título responde 200 e ordena de verdade, nos dois sentidos' do
      %w[Zeta Alfa Meio].each { |t| create(:carrier_group, title: t) }

      get '/api/v1/carrier_groups', params: { ordering_keys: ['title'], ordering_style: ['up'] },
                                    headers: auth_headers(og)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).map { |g| g['title'] }).to eq(%w[Alfa Meio Zeta])

      get '/api/v1/carrier_groups', params: { ordering_keys: ['title'], ordering_style: ['down'] },
                                    headers: auth_headers(og)
      expect(JSON.parse(response.body).map { |g| g['title'] }).to eq(%w[Zeta Meio Alfa])
    end

    it 'ordena por `carriers_count`' do
      cheio = create(:carrier_group, title: 'Cheio')
      create(:carrier_group, title: 'Vazio')
      2.times { create(:carrier, group: cheio) }

      get '/api/v1/carrier_groups', params: { ordering_keys: ['carriers_count'], ordering_style: ['down'] },
                                    headers: auth_headers(og)
      expect(JSON.parse(response.body).map { |g| g['title'] }).to eq(%w[Cheio Vazio])
    end
  end

  # 2.2.3 / OPS-058 — o `counter_cache` é o MESMO número que decide o 422.
  describe '`carriers_count` (OPS-058)' do
    it 'bate com `group.carriers.count` ao criar, mover e remover portador' do
      grupo = create(:carrier_group)
      outro = create(:carrier_group)

      portador = create(:carrier, group: grupo)
      expect(grupo.reload.carriers_count).to eq(grupo.carriers.count).and eq(1)

      portador.update!(group: outro)
      expect(grupo.reload.carriers_count).to eq(0)
      expect(outro.reload.carriers_count).to eq(1)

      portador.destroy!
      expect(outro.reload.carriers_count).to eq(0)
    end

    it 'o número exposto é o mesmo do banco' do
      grupo = create(:carrier_group)
      3.times { create(:carrier, group: grupo) }

      get "/api/v1/carrier_groups/#{grupo.id}", headers: auth_headers(og)
      expect(JSON.parse(response.body)['carriers_count']).to eq(3)
    end
  end

  # 4.3.4 / D-24 — no legado o botão sumia pela contagem e a exclusão passava
  # assim mesmo, deixando `group_id` órfão.
  describe 'DELETE — o critério do botão É o critério do servidor' do
    it 'grupo COM portadores → 422, e o `group_id` dos portadores PERMANECE' do
      grupo = create(:carrier_group)
      portador = create(:carrier, group: grupo)

      delete "/api/v1/carrier_groups/#{grupo.id}", headers: auth_headers(og)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to include('portador')
      expect(CarrierGroup.exists?(grupo.id)).to be(true)
      expect(portador.reload.group_id).to eq(grupo.id)
    end

    it 'grupo VAZIO é excluído' do
      grupo = create(:carrier_group)
      delete "/api/v1/carrier_groups/#{grupo.id}", headers: auth_headers(og)
      expect(response).to have_http_status(:ok)
      expect(CarrierGroup.exists?(grupo.id)).to be(false)
    end

    it 'o banco também recusa — a FK é real (DB-058)' do
      grupo = create(:carrier_group)
      create(:carrier, group: grupo)

      expect { ActiveRecord::Base.connection.execute("DELETE FROM carrier_groups WHERE id = '#{grupo.id}'") }
        .to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end
end

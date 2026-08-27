require 'rails_helper'

# Testes para expandir cobertura dos services restantes
RSpec.describe UsersService, type: :service do
  let!(:user) { create(:user, :og) }
  let!(:colaborador_user) { create(:user, :colaborador) }

  describe '.index' do
    it 'returns all users with pagination' do
      res = described_class.index({ page: 1, per_page: 10 })
      expect(res[:success]).to be true
      expect(res[:data]).to be_a(Hash)
      expect(res[:data][:users]).to be_an(Array)
    end

    it 'filters by search query' do
      res = described_class.index({ q: user.email })
      expect(res[:success]).to be true
    end
  end

  describe '.show' do
    it 'returns user by id' do
      res = described_class.show(id: user.id)
      expect(res[:success]).to be true
    end
  end

  describe '.update' do
    it 'updates user attributes' do
      res = described_class.update({ id: user.id, name: 'Updated Name' })
      expect(res[:success]).to be true
      expect(user.reload.name).to eq('Updated Name')
    end
  end
end

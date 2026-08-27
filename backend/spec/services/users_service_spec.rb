require 'rails_helper'

RSpec.describe UsersService, type: :service do
  let!(:user_type_colaborador) { create(:user_type, :colaborador) }
  let!(:user) { create(:user, user_type: user_type_colaborador, name: 'John Doe', email: 'john@example.com') }

  describe '.index' do
    it 'returns list of users' do
      response = described_class.index({})
      expect(response[:success]).to be true
      expect(response[:status]).to eq(200)
      # represent returns Entity or list of Entities. call as_json to get hash.
      users = response[:data][:users].as_json
      expect(users).to be_present
      ids = users.map { |u| u[:id] }
      expect(ids).to include(user.id)
    end

    it 'filters by search query' do
      response = described_class.index({ q: 'John' })
      vals = response[:data][:users].as_json.map { |u| u[:name] }
      expect(vals).to include('John Doe')
    end

    it 'filters by type' do
      og_user = create(:user, :og)
      response = described_class.index({ type: 'colaborador' })
      ids = response[:data][:users].as_json.map { |u| u[:id] }
      expect(ids).to include(user.id)
      expect(ids).not_to include(og_user.id)
    end
  end

  describe '.show' do
    it 'returns the user' do
      response = described_class.show({ id: user.id })
      expect(response[:success]).to be true
      expect(response[:data].as_json[:id]).to eq(user.id)
    end

    it 'returns 404 for non-existent user' do
      response = described_class.show({ id: 0 })
      expect(response[:success]).to be false
      expect(response[:status]).to eq(404)
    end
  end

  describe '.create' do
    let(:valid_params) do
      {
        name: 'New User',
        email: 'new@example.com',
        user_type_id: user_type_colaborador.id
      }
    end

    it 'creates a new user' do
      expect {
        response = described_class.create(valid_params)
        expect(response[:success]).to be true
      }.to change(User, :count).by(1)
    end

    it 'fails with invalid params' do
      response = described_class.create({ name: 'No Email' })
      expect(response[:success]).to be false
      expect(response[:status]).to eq(422)
    end
  end

  describe '.update' do
    it 'updates user attributes' do
      response = described_class.update({ id: user.id, name: 'Updated Name' })
      expect(response[:success]).to be true
      expect(user.reload.name).to eq('Updated Name')
    end

    it 'returns 404 if user not found' do
      response = described_class.update({ id: 0, name: 'Ghost' })
      expect(response[:status]).to eq(404)
    end
  end

  describe '.destroy' do
    it 'deletes the user' do
      expect {
        response = described_class.destroy({ id: user.id })
        expect(response[:success]).to be true
      }.to change(User, :count).by(-1)
    end
  end
end

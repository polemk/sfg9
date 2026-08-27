require 'rails_helper'

RSpec.describe Permission, type: :model do
  let!(:permission) { create(:permission, key: 'test_perm', title: 'Test Permission') }

  describe 'validations' do
    it 'requires key' do
      p = Permission.new(title: 'Test')
      expect(p.valid?).to be false
      expect(p.errors[:key]).to be_present
    end

    it 'requires title' do
      p = Permission.new(key: 'test')
      expect(p.valid?).to be false
      expect(p.errors[:title]).to be_present
    end

    it 'requires unique key' do
      p = Permission.new(key: 'test_perm', title: 'Another')
      expect(p.valid?).to be false
    end
  end

  describe 'scopes' do
    it '.active returns only active permissions' do
      inactive = create(:permission, is_active: false)
      expect(Permission.active).to include(permission)
      expect(Permission.active).not_to include(inactive)
    end
  end
end

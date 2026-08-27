require 'rails_helper'

RSpec.describe UserPermission, type: :model do
  let!(:user) { create(:user) }
  let!(:permission) { create(:permission) }

  describe 'validations' do
    it 'requires user' do
      up = UserPermission.new(permission: permission, source: 'manual', granted_at: Time.current)
      expect(up.valid?).to be false
    end

    it 'requires permission' do
      up = UserPermission.new(user: user, source: 'manual', granted_at: Time.current)
      expect(up.valid?).to be false
    end

    it 'requires source' do
      up = UserPermission.new(user: user, permission: permission, granted_at: Time.current)
      expect(up.valid?).to be false
    end

    it 'requires granted_at' do
      up = UserPermission.new(user: user, permission: permission, source: 'manual')
      expect(up.valid?).to be false
    end
  end

  describe 'scopes' do
    it '.active returns non-revoked permissions' do
      active = create(:user_permission, user: user, permission: permission)
      revoked = create(:user_permission, user: user, permission: create(:permission), revoked_at: Time.current)
      
      expect(UserPermission.active).to include(active)
      expect(UserPermission.active).not_to include(revoked)
    end
  end
end

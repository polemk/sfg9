# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PermissionConflict, type: :model do
  before do
    # Factories extracted to spec/factories/
  end

  describe 'associations' do
    it { is_expected.to belong_to(:permission) }
    it { is_expected.to belong_to(:conflicts_with).class_name('Permission') }
  end

  describe 'validations' do
    subject { create(:permission_conflict) }
    
    it do
      is_expected.to validate_uniqueness_of(:permission_id).scoped_to(:conflicts_with_id)
    end
  end
end

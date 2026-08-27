# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PermissionAuditLog, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:actor).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:change_type) }
  end
end

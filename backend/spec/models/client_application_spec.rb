# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClientApplication, type: :model do
  subject { build(:client_application) }

  before do
    # Factory extracted to spec/factories/client_applications.rb
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:token) }
    it { is_expected.to validate_uniqueness_of(:token) }
  end

  describe 'scopes' do
    let!(:active_app) { create(:client_application, active: true) }
    let!(:inactive_app) { create(:client_application, active: false) }

    describe '.active' do
      it 'returns only active applications' do
        expect(described_class.active).to include(active_app)
        expect(described_class.active).not_to include(inactive_app)
      end
    end
  end
end

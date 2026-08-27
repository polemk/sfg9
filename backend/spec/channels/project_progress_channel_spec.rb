# frozen_string_literal: true

require 'rails_helper'

# OPS-087 / OPS-128 — o canal de progresso, escopado por participação (C1).
RSpec.describe ProjectProgressChannel, type: :channel do
  before { UserType.seed_default_types! }

  let(:dono) { create(:user, user_type: UserType.admin) }
  let(:estranho) { create(:user, user_type: UserType.admin) }
  let(:projeto) { Project.create!(name: 'P', slug: 'p', owner: dono) }

  before { Membership.create!(project: projeto, user: dono, role: 'responsavel') }

  it 'ACEITA quem participa do projeto — e RECUSA quem não participa' do
    stub_connection current_user: dono
    subscribe(project_id: projeto.id)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("project_progress:#{projeto.id}")

    stub_connection current_user: estranho
    subscribe(project_id: projeto.id)
    expect(subscription).to be_rejected
  end

  it 'recusa sem project_id e sem sessão' do
    stub_connection current_user: dono
    subscribe(project_id: nil)
    expect(subscription).to be_rejected

    stub_connection current_user: nil
    subscribe(project_id: projeto.id)
    expect(subscription).to be_rejected
  end

  it 'publica no stream do projeto' do
    expect do
      described_class.publish(projeto.id, { kind: 'test', state: 'running' })
    end.to have_broadcasted_to("project_progress:#{projeto.id}")
  end
end

# frozen_string_literal: true

require 'rails_helper'

# OPS-005 / OPS-006 — o job de membro padrão.
RSpec.describe DefaultMemberJob do
  before { UserType.seed_default_types! }

  let(:dono) { create(:user, user_type: UserType.admin) }
  let!(:projeto_a) { Project.create!(name: 'A', slug: 'a', owner: dono) }
  let!(:projeto_b) { Project.create!(name: 'B', slug: 'b', owner: dono) }
  let!(:inativo)   { Project.create!(name: 'C', slug: 'c', owner: dono, is_active: false) }

  it 'insere o membro padrão em todos os projetos ATIVOS (e cruza projetos sem current_project!)' do
    user = create(:user, user_type: UserType.colaborador, is_default_member: true)

    expect(Membership.where(user: user).pluck(:project_id))
      .to contain_exactly(projeto_a.id, projeto_b.id)
    expect(Membership.where(user: user, project: inativo)).to be_empty
  end

  it 'é idempotente: rodar de novo não duplica' do
    user = create(:user, user_type: UserType.colaborador, is_default_member: true)
    expect { described_class.perform_now(user.id) }.not_to change(Membership, :count)
  end

  it 'ignora quem não é membro padrão' do
    user = create(:user, user_type: UserType.colaborador)
    expect(Membership.where(user: user)).to be_empty
  end

  describe 'gatilho (OPS-006)' do
    it 'enfileira SÓ quando is_default_member muda — não em todo update' do
      user = create(:user, user_type: UserType.colaborador)

      expect(described_class).not_to receive(:perform_later)
      user.update!(name: 'Outro nome')
      user.update!(phone: '5548911112222')
    end

    it 'enfileira quando a flag passa a verdadeira' do
      user = create(:user, user_type: UserType.colaborador)
      allow(described_class).to receive(:perform_later)

      user.update!(is_default_member: true)
      expect(described_class).to have_received(:perform_later).with(user.id).once
    end

    it 'não enfileira quando a flag é desligada' do
      user = create(:user, user_type: UserType.colaborador, is_default_member: true)
      allow(described_class).to receive(:perform_later)

      user.update!(is_default_member: false)
      expect(described_class).not_to have_received(:perform_later)
    end
  end

  describe 'falha visível' do
    it 'roda na fila de baixa prioridade, que existe no sidekiq.yml' do
      expect(described_class.new.queue_name).to include('low_priority')
    end
  end
end

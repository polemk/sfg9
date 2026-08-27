# frozen_string_literal: true

require 'rails_helper'

# F.6 / OPS-541 — os seeds de referência são **idempotentes**: rodar duas vezes
# não duplica nem reescreve papel já atribuído.
RSpec.describe 'Seeds de referência' do
  describe Seeds::Reference::UserTypes do
    it 'semeia exatamente os 4 papéis do Safegold na escala do ai9' do
      described_class.call!
      expect(UserType.pluck(:name, :hierarchy_level).sort_by(&:last))
        .to eq([['og', 1], ['admin', 2], ['gerente', 3], ['colaborador', 4]])
    end

    it 'rodar duas vezes não duplica' do
      described_class.call!
      expect { described_class.call! }.not_to change(UserType, :count)
    end

    it 'não reescreve papel já atribuído a usuário' do
      described_class.call!
      user = create(:user, user_type: UserType.admin)

      described_class.call!
      expect(user.reload.user_type).to eq(UserType.admin)
    end

    # DEC-41 parte 2
    it 'remove client/free/visitor e reatribui quem apontava para eles' do
      client = UserType.create!(name: 'client', description: 'legado', hierarchy_level: 2)
      UserType.create!(name: 'free', description: 'legado', hierarchy_level: 4)
      UserType.create!(name: 'og', description: 'legado', hierarchy_level: 1)
      orfao = create(:user, user_type: client)

      described_class.call!

      expect(UserType.where(name: %w[client free visitor])).to be_empty
      expect(orfao.reload.user_type.name).to eq('colaborador')
    end
  end

  describe Seeds::Reference::Permissions do
    it 'cria as 7 abilities com efeito real (DEC-108), com o tipo de cada uma' do
      described_class.call!
      expect(Permission.pluck(:key)).to contain_exactly(
        'user_is_readonly', 'may_create_users', 'may_invite_users', 'may_delete_users',
        'may_modify_public_entries', 'max_users_amount', 'max_invitations_amount'
      )
      expect(Permission.limits.pluck(:key)).to contain_exactly('max_users_amount', 'max_invitations_amount')
    end

    it 'semeia o default de cada papel com os valores do legado — sem inventar' do
      UserType.seed_default_types!
      described_class.call!

      def concedida?(papel, chave)
        UserTypePermission.granted.joins(:permission)
                          .exists?(user_type: UserType.public_send(papel), permissions: { key: chave })
      end

      # `db/seeds.rb:51` (Admin tem) vs o bloco do Gerente `:62-80` (ausente).
      expect(concedida?(:admin, 'may_create_users')).to be(true)
      expect(concedida?(:gerente, 'may_create_users')).to be(false)
      # `db/seeds.rb:53,66` — Admin e Gerente convidam; o Colaborador não.
      expect(concedida?(:gerente, 'may_invite_users')).to be(true)
      expect(concedida?(:colaborador, 'may_invite_users')).to be(false)

      def teto(papel, chave)
        UserTypePermission.joins(:permission)
                          .find_by(user_type: UserType.public_send(papel), permissions: { key: chave })
                          &.limit_value
      end

      # `db/seeds.rb:78,93` — Gerente 50, Colaborador 0. O OG fica **sem teto**
      # (divergência deliberada, ver o cabeçalho do seed).
      expect(teto(:gerente, 'max_invitations_amount')).to eq(50)
      expect(teto(:colaborador, 'max_invitations_amount')).to eq(0)
      expect(teto(:og, 'max_users_amount')).to be_nil
    end

    it 'rodar duas vezes não duplica' do
      described_class.call!
      expect { described_class.call! }.not_to change(Permission, :count)
    end

    it 'não revoga concessão existente ao rodar de novo' do
      described_class.call!
      UserType.seed_default_types!
      user = create(:user, user_type: UserType.colaborador)
      UserPermission.create!(user: user, permission: Permission.find_by!(key: 'user_is_readonly'),
                             source: 'manual', granted_at: Time.current)

      described_class.call!
      expect(user.reload.readonly_access?).to be(true)
    end
  end
end

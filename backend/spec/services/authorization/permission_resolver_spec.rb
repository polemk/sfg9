# frozen_string_literal: true

require 'rails_helper'

# 5.3.5 — regressão do **D-35**.
#
# No legado a `Role` CLONAVA as 17 abilities no momento da atribuição, então
# alterar a permissão do papel não alcançava quem já existia. Aqui a permissão é
# **consulta**, e o defeito desaparece por construção — não por correção.
RSpec.describe Authorization::PermissionResolver do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:permission) { Permission.find_by(key: 'user_is_readonly') }
  let(:colaborador) { create(:user, user_type: UserType.colaborador) }

  # **DEC-108** — o seed de referência passou a criar a linha de default de cada
  # papel (antes só criava o catálogo). Então o que o exemplo faz é *alterar* o
  # default, não inseri-lo: um `create!` aqui bate na unicidade
  # `(user_type_id, permission_id)` e a falha não teria nada a ver com o D-35,
  # que é o que este arquivo prova.
  def definir_default(user_type, permission, granted)
    record = UserTypePermission.find_or_initialize_by(user_type: user_type, permission: permission)
    record.granted = granted
    record.save!
    record
  end

  describe 'default do papel' do
    it 'conceder ao PAPEL afeta usuário JÁ EXISTENTE — e revogar volta atrás' do
      # O usuário existe ANTES da concessão. É esse o cenário do D-35.
      expect(described_class.new(colaborador).granted?('user_is_readonly')).to be(false)

      grant = definir_default(UserType.colaborador, permission, true)
      expect(described_class.new(colaborador).granted?('user_is_readonly')).to be(true)

      grant.update!(granted: false)
      expect(described_class.new(colaborador).granted?('user_is_readonly')).to be(false)
    end

    it 'a concessão de um papel NÃO vaza para outro papel' do
      admin_user = create(:user, user_type: UserType.admin)
      definir_default(UserType.colaborador, permission, true)

      expect(described_class.new(colaborador).granted?('user_is_readonly')).to be(true)
      expect(described_class.new(admin_user).granted?('user_is_readonly')).to be(false)
    end
  end

  describe 'override do usuário' do
    it 'concede a UM usuário sem afetar os outros do mesmo papel' do
      outro = create(:user, user_type: UserType.colaborador)
      UserPermission.create!(user: colaborador, permission: permission, source: 'manual', granted_at: Time.current)

      expect(described_class.new(colaborador).granted?('user_is_readonly')).to be(true)
      expect(described_class.new(outro).granted?('user_is_readonly')).to be(false)
    end

    it 'concessão revogada (revoked_at) deixa de valer' do
      up = UserPermission.create!(user: colaborador, permission: permission, source: 'manual',
                                  granted_at: Time.current)
      expect(described_class.new(colaborador).granted?('user_is_readonly')).to be(true)

      up.update!(revoked_at: Time.current)
      expect(described_class.new(colaborador).granted?('user_is_readonly')).to be(false)
    end
  end

  describe 'nada é congelado no usuário' do
    it 'a permissão NÃO é copiada para nenhuma coluna de users' do
      # Se algum dia alguém "otimizar" isto para uma coluna, o D-35 volta.
      expect(User.column_names).not_to include('permissions')
      expect(User.column_names.grep(/readonly/)).to be_empty
    end

    it 'a resolução consulta o banco a cada instância nova' do
      resolver = described_class.new(colaborador)
      expect(resolver.granted?('user_is_readonly')).to be(false)

      definir_default(UserType.colaborador, permission, true)

      # A instância antiga memoiza dentro da requisição (correto);
      # a instância nova — que é o que cada request cria — já vê a mudança.
      expect(resolver.granted?('user_is_readonly')).to be(false)
      expect(described_class.new(colaborador).granted?('user_is_readonly')).to be(true)
    end
  end

  describe 'permissão inativa' do
    it 'não é concedida mesmo com grant ativo' do
      UserPermission.create!(user: colaborador, permission: permission, source: 'manual', granted_at: Time.current)
      permission.update!(is_active: false)

      expect(described_class.new(colaborador).granted?('user_is_readonly')).to be(false)
    end
  end
end

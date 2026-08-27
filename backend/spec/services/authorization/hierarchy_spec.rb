# frozen_string_literal: true

require 'rails_helper'

# Contrato **C3** — a trava de hierarquia.
#
# **Todo exemplo aqui verifica os DOIS lados.** Um teste que só verifique que a
# trava existe **passa com o sinal invertido**, porque a trava continua
# existindo: está apontando para o lado errado. E inverter o sinal aqui dá poder
# de OG a um Colaborador.
RSpec.describe Authorization::Hierarchy do
  before { UserType.seed_default_types! }

  let(:og)          { create(:user, user_type: UserType.og) }
  let(:admin)       { create(:user, user_type: UserType.admin) }
  let(:admin2)      { create(:user, user_type: UserType.admin) }
  let(:gerente)     { create(:user, user_type: UserType.gerente) }
  let(:colaborador) { create(:user, user_type: UserType.colaborador) }

  describe '.can_edit_user_type? — 5.1.1 e 5.1.2' do
    it 'Admin NÃO edita o papel OG — e EDITA o papel Colaborador' do
      expect(described_class.can_edit_user_type?(admin, UserType.og)).to be(false)
      expect(described_class.can_edit_user_type?(admin, UserType.colaborador)).to be(true)
    end

    it 'Admin NÃO edita outro Admin (lateral) — e o OG edita o papel de todos' do
      expect(described_class.can_edit_user_type?(admin, UserType.admin)).to be(false)
      expect(described_class.can_edit_user_type?(og, UserType.admin)).to be(true)
      expect(described_class.can_edit_user_type?(og, UserType.og)).to be(true)
      expect(described_class.can_edit_user_type?(og, UserType.colaborador)).to be(true)
    end

    it 'Gerente não alcança nenhum papel — e o Admin alcança o Gerente (DEC-18.2)' do
      expect(described_class.can_edit_user_type?(gerente, UserType.colaborador)).to be(false)
      expect(described_class.can_edit_user_type?(admin, UserType.gerente)).to be(true)
    end
  end

  describe '.can_edit_user_permissions? — 5.1.1 aplicada ao usuário (D-34)' do
    it 'Admin NÃO edita permissão de um OG — e EDITA a de um Colaborador' do
      expect(described_class.can_edit_user_permissions?(admin, og)).to be(false)
      expect(described_class.can_edit_user_permissions?(admin, colaborador)).to be(true)
    end

    it 'Admin NÃO edita permissão de outro Admin nem a própria — e o OG edita a de qualquer um' do
      expect(described_class.can_edit_user_permissions?(admin, admin2)).to be(false)
      expect(described_class.can_edit_user_permissions?(admin, admin)).to be(false)
      expect(described_class.can_edit_user_permissions?(og, admin)).to be(true)
    end
  end

  describe '.can_view_user_type?' do
    it 'Admin VÊ o próprio papel (leitura) — mas NÃO vê o do OG' do
      expect(described_class.can_view_user_type?(admin, UserType.admin)).to be(true)
      expect(described_class.can_view_user_type?(admin, UserType.og)).to be(false)
    end
  end

  describe '.can_impersonate? — DEC-18.3' do
    it 'OG personifica um Colaborador — e NÃO personifica a si mesmo' do
      expect(described_class.can_impersonate?(og, colaborador)).to be(true)
      expect(described_class.can_impersonate?(og, og)).to be(false)
    end

    it 'Admin personifica Colaborador — e NÃO personifica OG nem outro Admin' do
      expect(described_class.can_impersonate?(admin, colaborador)).to be(true)
      expect(described_class.can_impersonate?(admin, og)).to be(false)
      expect(described_class.can_impersonate?(admin, admin2)).to be(false)
    end

    it 'Gerente e Colaborador não personificam ninguém — e o OG personifica o Gerente' do
      expect(described_class.can_impersonate?(gerente, colaborador)).to be(false)
      expect(described_class.can_impersonate?(colaborador, gerente)).to be(false)
      expect(described_class.can_impersonate?(og, gerente)).to be(true)
    end
  end

  # 5.1.4
  describe '.visible_user_types' do
    it 'o filtro do Gerente NÃO devolve OG nem Admin — e DEVOLVE Colaborador' do
      names = described_class.visible_user_types(gerente).pluck(:name)
      expect(names).not_to include('og')
      expect(names).not_to include('admin')
      expect(names).to include('colaborador')
      expect(names).to include('gerente')
    end

    it 'o OG enxerga todos os 4 papéis' do
      expect(described_class.visible_user_types(og).pluck(:name))
        .to contain_exactly('og', 'admin', 'gerente', 'colaborador')
    end

    it 'o Admin enxerga do próprio nível para baixo, nunca o OG' do
      names = described_class.visible_user_types(admin).pluck(:name)
      expect(names).to contain_exactly('admin', 'gerente', 'colaborador')
    end
  end
end

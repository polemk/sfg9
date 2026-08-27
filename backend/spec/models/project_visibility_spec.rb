# frozen_string_literal: true

require 'rails_helper'

# DEC-99 — OG e Admin enxergam TODOS os projetos; Gerente e Colaborador só os
# seus.
#
# Cada caso é verificado **nos dois sentidos**, pela mesma disciplina do contrato
# C3: um teste que só confirma que "o administrador vê" passaria mesmo se o
# escopo tivesse sumido para todo mundo, e um que só confirma que "o colaborador
# não vê o alheio" passaria mesmo se ninguém visse nada. O par é o que prova que
# a regra está apontando para o lado certo.
RSpec.describe 'Project.visible_to', type: :model do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call! if defined?(Seeds::Reference::Permissions)
  end

  let!(:dono)  { create(:user, :gerente) }
  let!(:alpha) { create_project_with_owner(dono, name: 'Alpha') }
  let!(:beta)  { create_project_with_owner(dono, name: 'Beta') }

  def com_papel(slug)
    tipo = UserType.find_by('LOWER(name) = ?', slug)
    create(:user, user_type: tipo)
  end

  describe 'OG' do
    let(:og) { com_papel('og') }

    it 'enxerga todos os projetos MESMO SEM participação nenhuma' do
      expect(Project.for_member(og)).to be_empty
      expect(Project.visible_to(og)).to include(alpha, beta)
    end
  end

  describe 'Admin' do
    let(:admin) { com_papel('admin') }

    it 'enxerga todos os projetos MESMO SEM participação nenhuma' do
      expect(Project.for_member(admin)).to be_empty
      expect(Project.visible_to(admin)).to include(alpha, beta)
    end
  end

  describe 'Gerente' do
    let(:gerente) { com_papel('gerente') }

    before { Membership.create!(user: gerente, project: alpha) }

    it 'enxerga o projeto em que participa' do
      expect(Project.visible_to(gerente)).to include(alpha)
    end

    it 'NÃO enxerga projeto em que não participa' do
      expect(Project.visible_to(gerente)).not_to include(beta)
    end
  end

  describe 'Colaborador' do
    let(:colaborador) { com_papel('colaborador') }

    before { Membership.create!(user: colaborador, project: beta) }

    it 'enxerga o projeto em que participa' do
      expect(Project.visible_to(colaborador)).to include(beta)
    end

    it 'NÃO enxerga projeto em que não participa' do
      expect(Project.visible_to(colaborador)).not_to include(alpha)
    end
  end

  describe 'for_member continua significando participação literal' do
    let(:og) { com_papel('og') }

    it 'não passa a devolver tudo só porque o usuário é OG' do
      # Se alguém "simplificar" fundindo os dois escopos, a remoção de membro e o
      # cálculo de "sobrou participação?" passam a mentir para OG e Admin.
      expect(Project.for_member(og)).to be_empty
    end
  end
end

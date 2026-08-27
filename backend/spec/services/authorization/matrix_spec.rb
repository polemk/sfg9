# frozen_string_literal: true

require 'rails_helper'

# BE-079 / DEC-18 — a matriz declarativa. Fonte:
# `.migration-ai9/authorization-matrix.md`, contrato aprovado em 24/08/2026.
RSpec.describe Authorization::Matrix do
  it 'cobre os 4 papéis em todos os recursos' do
    described_class.resources.each do |resource|
      described_class::ROLE_ORDER.each do |role|
        expect { described_class.actions_for(role, resource) }.not_to raise_error
      end
    end
  end

  it 'FALHA ALTO em recurso desconhecido — em vez de negar em silêncio' do
    expect { described_class.allow?('og', 'recebiveis_typo', :read) }
      .to raise_error(described_class::UnknownResource, /matriz de autorização/)
  end

  describe 'catálogos globais — DEC-18.4' do
    it 'Colaborador LÊ o catálogo — e NÃO escreve' do
      %w[carriers segments sub_segments wallets receivable_kinds risk_operation_types].each do |catalog|
        expect(described_class.allow?('colaborador', catalog, :read)).to be(true), catalog
        expect(described_class.allow?('colaborador', catalog, :create)).to be(false), catalog
        expect(described_class.allow?('colaborador', catalog, :update)).to be(false), catalog
        expect(described_class.allow?('colaborador', catalog, :destroy)).to be(false), catalog
      end
    end
  end

  describe 'users — DEC-18 decisão #3' do
    it 'Gerente LÊ usuários — e NÃO cria nem remove' do
      expect(described_class.allow?('gerente', 'users', :read)).to be(true)
      expect(described_class.allow?('gerente', 'users', :create)).to be(false)
      expect(described_class.allow?('gerente', 'users', :destroy)).to be(false)
    end

    it 'Colaborador não alcança usuários — e o Admin faz CRUD' do
      expect(described_class.allow?('colaborador', 'users', :read)).to be(false)
      %i[read create update destroy].each do |action|
        expect(described_class.allow?('admin', 'users', action)).to be(true)
      end
    end
  end

  describe 'permissions — DEC-18.2' do
    it 'Gerente NÃO alcança — e OG e Admin alcançam' do
      expect(described_class.allow?('gerente', 'permissions', :read)).to be(false)
      expect(described_class.allow?('gerente', 'permissions', :update)).to be(false)
      expect(described_class.allow?('admin', 'permissions', :update)).to be(true)
      expect(described_class.allow?('og', 'permissions', :update)).to be(true)
    end
  end

  describe 'grupo Admin — o Gerente não entra' do
    it 'Gerente não alcança help_items nem app_themes — e o Admin alcança' do
      expect(described_class.allow?('gerente', 'help_items', :read)).to be(false)
      expect(described_class.allow?('gerente', 'app_themes', :update)).to be(false)
      expect(described_class.allow?('admin', 'help_items', :update)).to be(true)
      expect(described_class.allow?('admin', 'app_themes', :update)).to be(true)
    end
  end

  describe 'grupo Projeto — DEC-15.1: os 4 itens `locked` nascem HABILITADOS' do
    it 'Colaborador faz CRUD em charges, availability e project_availabilities' do
      %w[charges availability project_availabilities availability_templates].each do |resource|
        expect(described_class.allow?('colaborador', resource, :read)).to be(true), resource
      end
      expect(described_class.allow?('colaborador', 'charges', :create)).to be(true)
      expect(described_class.allow?('colaborador', 'project_availabilities', :create)).to be(true)
      # `availability_templates` é catálogo global: leitura sim, escrita não.
      expect(described_class.allow?('colaborador', 'availability_templates', :create)).to be(false)
    end
  end

  describe 'trilha de auditoria — DEC-77' do
    it 'OG e Admin leem a trilha global — Gerente e Colaborador não' do
      expect(described_class.allow?('og', 'audit_trail', :read)).to be(true)
      expect(described_class.allow?('admin', 'audit_trail', :read)).to be(true)
      expect(described_class.allow?('gerente', 'audit_trail', :read)).to be(false)
      expect(described_class.allow?('colaborador', 'audit_trail', :read)).to be(false)
    end
  end

  describe 'impersonação — DEC-18.3' do
    it 'OG e Admin iniciam — Gerente e Colaborador não' do
      expect(described_class.allow?('og', 'impersonation', :create)).to be(true)
      expect(described_class.allow?('admin', 'impersonation', :create)).to be(true)
      expect(described_class.allow?('gerente', 'impersonation', :create)).to be(false)
      expect(described_class.allow?('colaborador', 'impersonation', :create)).to be(false)
    end
  end

  it 'papel inexistente não recebe nada' do
    expect(described_class.allow?('visitor', 'dash', :read)).to be(false)
    expect(described_class.allow?(nil, 'dash', :read)).to be(false)
  end
end

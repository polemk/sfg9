# frozen_string_literal: true

require 'rails_helper'

# BE-449 — ordenação multi-coluna dirigida pelo cliente, com allowlist.
RSpec.describe Sfg::Sortable do
  subject(:ordenacao) do
    described_class.new(
      allowed: { 'title' => :name, 'key' => :slug, 'criado' => :created_at },
      default: { name: :asc }
    )
  end

  describe '#build — a allowlist é o portão' do
    it 'casa os arrays paralelos por índice, como o legado' do
      expect(ordenacao.build(%w[title key], %w[up down]))
        .to eq({ name: :asc, slug: :desc })
    end

    it 'chave fora da allowlist é IGNORADA, não interpolada' do
      # `created_at` é o nome REAL da coluna; a chave pública é `criado`.
      # Mandar o nome da coluna não ordena — a allowlist é por chave pública.
      expect(ordenacao.build(%w[title created_at], %w[up up]))
        .to eq({ name: :asc })
    end

    it 'nenhum valor do cliente vira nome de coluna' do
      # O que sai é sempre um símbolo da allowlist — nunca a string recebida.
      resultado = ordenacao.build(['title; DROP TABLE users --'], ['up'])
      expect(resultado).to be_empty
    end

    it 'estilo desconhecido cai em `asc` em vez de derrubar o request' do
      # No legado `get_ordering_style` devolve `nil` e a linha seguinte faz
      # `"name " + nil` → TypeError → 500.
      expect(ordenacao.build(%w[title], %w[lateral])).to eq({ name: :asc })
    end

    it 'estilo ausente também cai em `asc`' do
      expect(ordenacao.build(%w[title key], nil)).to eq({ name: :asc, slug: :asc })
    end

    it 'aceita os nomes canônicos além do `up`/`down` do legado' do
      expect(ordenacao.build(%w[title key], %w[desc ascending])).to eq({ name: :desc, slug: :asc })
    end

    it 'limita o número de colunas' do
      chaves = ['title'] * 20
      expect(ordenacao.build(chaves, nil).size).to be <= described_class::MAX_COLUMNS
    end
  end

  describe '#rejected' do
    it 'informa o que foi recusado, para a tela poder avisar' do
      expect(ordenacao.rejected(%w[title inexistente])).to eq(['inexistente'])
    end
  end

  describe '#apply' do
    before do
      UserType.seed_default_types!
      dono = create(:user, user_type: UserType.og)
      Project.create!(name: 'Beta', slug: 'beta', owner: dono)
      Project.create!(name: 'Alfa', slug: 'alfa', owner: dono)
    end

    it 'ordena pelo que a allowlist permite' do
      nomes = ordenacao.apply(Project.all, keys: %w[title], styles: %w[down]).pluck(:name)
      expect(nomes).to eq(%w[Beta Alfa])
    end

    it 'sem chave válida, vale a ordem padrão — a lista não sai embaralhada' do
      nomes = ordenacao.apply(Project.all, keys: %w[nao_existe], styles: %w[up]).pluck(:name)
      expect(nomes).to eq(%w[Alfa Beta])
    end

    it 'gera SQL sem nada vindo do cliente' do
      sql = ordenacao.apply(Project.all, keys: ['title; --'], styles: ['up']).to_sql
      expect(sql).not_to include('DROP')
      expect(sql).not_to include('--')
    end
  end
end

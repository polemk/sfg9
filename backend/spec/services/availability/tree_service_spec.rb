# frozen_string_literal: true

require 'rails_helper'

# S11 / DB-131, BE-137, BE-138, BE-116 — **a numeração e a ordem da árvore**.
#
# Os quatro defeitos que estes exemplos travam, todos medidos no legado:
#
#  1. **ordenação lexicográfica** — `position` era string e 12 irmãos saíam
#     `1, 10, 11, 12, 2, 3…`;
#  2. **nível por OR bit a bit** (` |= `) — um filho de nível 2 herdando de 5
#     virava 7;
#  3. **colisão em criação concorrente** — `max + 1` lido por dois processos;
#  4. **reordenação quadrática** — os três `import` rodavam **dentro** do laço
#     de 1º nível (`project.rb:266-268`).
RSpec.describe Availability::TreeService do
  let(:project) { create(:project) }

  def padrao(**atributos)
    create(:project_availability_template, project: project, **atributos)
  end

  describe 'ordenação (DB-131)' do
    it '12 irmãos ordenam 1,2,…,10,11,12 — o legado colocava "10" antes de "2"' do
      titulos = (1..12).map { |n| padrao(title: "Item #{n}").title }

      ordem = ProjectAvailabilityTemplate.for_project(project).in_tree_order.pluck(:title)

      expect(ordem).to eq(titulos)
      expect(ProjectAvailabilityTemplate.for_project(project).in_tree_order.pluck(:position))
        .to eq((1..12).to_a)
    end

    it 'a árvore sai em ordem de profundidade — pai, filhos, netos' do
      a = padrao(title: 'A')
      b = padrao(title: 'B')
      a1 = padrao(title: 'A1', parent_template_id: a.id)
      a1x = padrao(title: 'A1x', parent_template_id: a1.id)
      a2 = padrao(title: 'A2', parent_template_id: a.id)

      expect(ProjectAvailabilityTemplate.for_project(project).in_tree_order.pluck(:title))
        .to eq(%w[A A1 A1x A2 B])
      expect([a, a1, a1x, a2, b].map { |t| t.reload.position_path })
        .to eq(['1', '1.1', '1.1.1', '1.2', '2'])
    end
  end

  describe 'nível derivado do pai (BE-137 / BE-112)' do
    it 'é sempre `parent.level + 1`' do
      raiz = padrao
      filho = padrao(parent_template_id: raiz.id)
      neto = padrao(parent_template_id: filho.id)

      expect([raiz.level, filho.level, neto.level]).to eq([1, 2, 3])
    end

    it 'recusa um quarto nível em vez de somar por OR bit a bit' do
      raiz = padrao
      filho = padrao(parent_template_id: raiz.id)
      neto = padrao(parent_template_id: filho.id)

      bisneto = build(:project_availability_template, project: project, parent_template_id: neto.id)

      expect(bisneto).not_to be_valid
      expect(bisneto.errors[:parent_template_id].join).to include('3 níveis')
    end

    it 'sobe `top_parent_id` até a raiz, sem o default 0 do legado' do
      raiz = padrao
      filho = padrao(parent_template_id: raiz.id)
      neto = padrao(parent_template_id: filho.id)

      expect(raiz.top_parent_id).to be_nil
      expect(filho.top_parent_id).to eq(raiz.id)
      expect(neto.top_parent_id).to eq(raiz.id)
      expect(AvailabilityTemplate.where(top_parent_id: nil).where.not(parent_template_id: nil)).to be_empty
    end
  end

  describe 'criação concorrente (BE-137 / 6.4.3)' do
    it 'duas criações no mesmo grupo de irmãos não colidem em posição' do
      padrao(title: 'existente')

      # **Limite honesto deste exemplo:** com `use_transactional_fixtures`, o
      # Rails trava a conexão na thread principal e as duas threads acabam na
      # MESMA sessão do Postgres — então o `pg_advisory_xact_lock` não é
      # exercitado de verdade aqui. O que este exemplo prova é que a atribuição
      # de posição intercalada não produz duplicata; a serialização entre
      # processos distintos está no código (`lock_sibling_group!`) e só um teste
      # com banco não transacional a exerceria.
      linhas = 2.times.map do |i|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            registro = ProjectAvailabilityTemplate.new(project_id: project.id, title: "Concorrente #{i}",
                                                       operation_type: 'C', deadline_type: 'CP')
            described_class.assign_next_position!(registro)
            registro.save!
            registro.position
          end
        end
      end.map(&:value)

      expect(linhas.uniq.size).to eq(2)
      expect(ProjectAvailabilityTemplate.for_project(project).pluck(:position).uniq.size).to eq(3)
    end
  end

  describe 'reordenação (BE-138)' do
    it 'move dentro do grupo de irmãos e reescreve a chave dos descendentes' do
      a = padrao(title: 'A')
      b = padrao(title: 'B')
      c = padrao(title: 'C')
      a1 = padrao(title: 'A1', parent_template_id: a.id)

      ok, = described_class.move!(a, 3)

      expect(ok).to be(true)
      expect(ProjectAvailabilityTemplate.for_project(project).roots.in_tree_order.pluck(:title))
        .to eq(%w[B C A])
      expect([b, c, a].map { |t| t.reload.position }).to eq([1, 2, 3])
      # O filho acompanhou o pai: a chave dele passou a começar por "0003".
      expect(a1.reload.position_path).to eq('3.1')
    end

    it 'recusa posição fora do intervalo — no servidor, não na tela' do
      a = padrao
      padrao

      ok, mensagem = described_class.move!(a, 9)

      expect(ok).to be(false)
      expect(mensagem).to include('entre 1 e 2')
      expect(a.reload.position).to eq(1)
    end
  end

  describe 'renumeração da árvore (BE-116)' do
    it 'fecha buracos deixados por remoção' do
      a = padrao(title: 'A')
      b = padrao(title: 'B')
      c = padrao(title: 'C')

      b.destroy!
      described_class.reorder_project!(project)

      expect([a.reload.position, c.reload.position]).to eq([1, 2])
    end

    it 'o custo NÃO cresce com o quadrado dos nós — o legado importava dentro do laço' do
      12.times { |n| padrao(title: "N#{n}") }

      consultas = 0
      assinante = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        consultas += 1 unless payload[:name].to_s.in?(%w[SCHEMA TRANSACTION CACHE])
      end
      described_class.reorder_project!(project)
      ActiveSupport::Notifications.unsubscribe(assinante)

      # Linear: uma leitura + no máximo uma gravação por nó. Quadrático em 12 nós
      # passaria de 140 consultas.
      expect(consultas).to be < 40
    end
  end
end

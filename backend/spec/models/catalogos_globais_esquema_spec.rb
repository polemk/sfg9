# frozen_string_literal: true

require 'rails_helper'

# S3 / tarefas 1.11 e F.1 — **o esquema dos cinco catálogos globais**.
#
# O legado tinha **zero** `add_foreign_key` na base inteira: `group_id` órfão
# apontando para grupo apagado era normal. Este spec é o script que a tarefa
# 1.11 pede, escrito como teste para não depender de alguém lembrar de rodá-lo.
RSpec.describe 'Esquema dos catálogos globais', type: :model do
  TABELAS = %w[carriers carrier_groups segments sub_segments project_guarantee_types].freeze

  let(:conexao) { ActiveRecord::Base.connection }

  it 'as cinco tabelas existem — e não há uma SEGUNDA família para os mesmos recursos (F.1)' do
    TABELAS.each { |t| expect(conexao.table_exists?(t)).to be(true), "#{t} não existe" }

    # Nomes que uma segunda implementação dos mesmos catálogos usaria.
    duplicatas = %w[bank_carriers carrier_types business_segments guarantee_types]
    duplicatas.each do |t|
      expect(conexao.table_exists?(t)).to be(false), "#{t} é uma segunda família para o mesmo recurso"
    end
  end

  # 1.11 — o script pedido pela tarefa, virado teste.
  it 'toda coluna `*_id` tem `add_foreign_key` e índice' do
    sem_fk = []
    sem_indice = []

    TABELAS.each do |tabela|
      fks = conexao.foreign_keys(tabela).map { |f| f.options[:column].to_s }
      indices = conexao.indexes(tabela).flat_map(&:columns).map(&:to_s)

      conexao.columns(tabela).map(&:name).grep(/_id\z/).each do |coluna|
        # `legacy_id` é a PK do LEGADO (DEC-12), não referência a tabela do ai9:
        # não há para onde apontar uma FK. O índice único, esse, é exigido.
        if coluna == 'legacy_id'
          expect(indices).to include(coluna), "#{tabela}.legacy_id sem índice"
          next
        end

        sem_fk << "#{tabela}.#{coluna}" unless fks.include?(coluna)
        sem_indice << "#{tabela}.#{coluna}" unless indices.include?(coluna)
      end
    end

    expect(sem_fk).to be_empty, "colunas *_id sem FK: #{sem_fk.join(', ')}"
    expect(sem_indice).to be_empty, "colunas *_id sem índice: #{sem_indice.join(', ')}"
  end

  it 'as cinco tabelas nascem com id `uuid` — o padrão de id do ai9' do
    TABELAS.each do |tabela|
      tipo = conexao.columns(tabela).find { |c| c.name == 'id' }.sql_type
      expect(tipo).to eq('uuid'), "#{tabela}.id é #{tipo}"
    end
  end

  # A outra ponta da Regra de fronteira: quem consome os catálogos criados aqui.
  it '`projects` aponta para `segments` e `sub_segments` com FK real e tipo casando' do
    colunas = conexao.columns(:projects).index_by(&:name)
    expect(colunas['segment_id'].sql_type).to eq('uuid')
    expect(colunas['sub_segment_id'].sql_type).to eq('uuid')

    destinos = conexao.foreign_keys(:projects).map { |f| f.to_table }
    expect(destinos).to include('segments', 'sub_segments')
  end

  it 'toda coluna dos cinco cadastros tem `comment:`' do
    sem_comentario = TABELAS.flat_map do |tabela|
      conexao.columns(tabela)
             .reject { |c| %w[id created_at updated_at].include?(c.name) }
             .select { |c| c.comment.blank? }
             .map { |c| "#{tabela}.#{c.name}" }
    end

    expect(sem_comentario).to be_empty, "colunas sem comentário: #{sem_comentario.join(', ')}"
  end
end

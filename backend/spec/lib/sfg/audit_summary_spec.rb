# frozen_string_literal: true

require 'rails_helper'

# S19 — a frase da trilha, e os dois verbetes que o legado tinha como função.
RSpec.describe Sfg::AuditSummary do
  describe '.call — concordância de gênero vem do catálogo (FE-432)' do
    it 'concorda no feminino' do
      expect(described_class.call(item_type: 'UserPermission', event: 'create'))
        .to eq('A permissão do usuário foi criada')
    end

    it 'concorda no masculino' do
      expect(described_class.call(item_type: 'Project', event: 'update'))
        .to eq('O projeto foi alterado')
    end

    it 'cobre os três eventos do paper_trail' do
      expect(described_class.call(item_type: 'Membership', event: 'destroy'))
        .to eq('A participação no projeto foi removida')
    end
  end

  describe 'a frase não pode fazer o evento sumir' do
    # No legado, `resume` era `string` com `maximum: 300` e o `save` sem
    # verificação: resumo longo = evento inexistente. Aqui a frase é derivada.
    it 'tipo sem verbete continua produzindo frase, não exceção' do
      expect { described_class.call(item_type: 'TipoQueNaoExiste', event: 'create') }
        .not_to raise_error
      expect(described_class.call(item_type: 'TipoQueNaoExiste', event: 'create'))
        .to include('foi criado')
    end

    it 'evento desconhecido também' do
      expect(described_class.call(item_type: 'Project', event: 'algo'))
        .to eq('O projeto foi alterado')
    end
  end

  describe '.known_types' do
    it 'alimenta o filtro da tela sem ela conhecer a lista de models' do
      expect(described_class.known_types).to include('User', 'Project', 'UserPermission')
    end
  end
end

# FE-438 — plural simplificado vira dado, não `string + "s"`.
RSpec.describe Sfg::Inflection do
  describe '.pluralize' do
    it 'no singular não flexiona' do
      expect(described_class.pluralize(1, 'permissão')).to eq('1 permissão')
    end

    it 'usa a forma declarada no catálogo' do
      expect(described_class.pluralize(3, 'permissão')).to eq('3 permissões')
      expect(described_class.pluralize(2, 'renegociação')).to eq('2 renegociações')
      expect(described_class.pluralize(2, 'recebível')).to eq('2 recebíveis')
      expect(described_class.pluralize(2, 'papel')).to eq('2 papéis')
    end

    it 'zero é plural' do
      expect(described_class.pluralize(0, 'projeto')).to eq('0 projetos')
    end

    it 'sem forma declarada cai na regra regular' do
      expect(described_class.plural('projeto')).to eq('projetos')
      expect(described_class.plural('contrato')).to eq('contratos')
      expect(described_class.plural('mês')).to eq('mêses') # regra; exceção vai ao catálogo
    end

    it 'as regras cobrem o que o `+ "s"` do legado errava' do
      expect(described_class.plural('funil')).to eq('funis')
      expect(described_class.plural('item')).to eq('itens')
      expect(described_class.plural('valor')).to eq('valores')
    end

    it 'devolve só a palavra quando pedido' do
      expect(described_class.pluralize(2, 'projeto', com_numero: false)).to eq('projetos')
    end
  end
end

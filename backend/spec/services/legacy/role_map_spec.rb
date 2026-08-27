# frozen_string_literal: true

require 'rails_helper'

# 5.1.5 — o de-para do ETL é **tabela explícita, nunca fórmula**.
#
# O ponto do exemplo negativo: uma fórmula (`1111 → 1`, `998 → 2`, …) sobrevive a
# um valor inesperado e produz um nível **plausível e errado**. A tabela falha
# alto, que é o comportamento desejado.
RSpec.describe Legacy::RoleMap do
  before { UserType.seed_default_types! }

  describe '.resolve' do
    {
      1111 => 'og',
      998 => 'admin',
      888 => 'gerente',
      799 => 'colaborador'
    }.each do |legacy, expected|
      it "mapeia hierarchy #{legacy} para `#{expected}`" do
        role, exception = described_class.resolve(hierarchy: legacy)
        expect(role).to eq(expected)
        expect(exception).to be(false)
      end
    end

    it 'mapeia pelo nome literal do RoleType do legado' do
      expect(described_class.resolve(name: 'Gerente').first).to eq('gerente')
      expect(described_class.resolve(name: 'Colaborador').first).to eq('colaborador')
    end

    # D-36 / DEC-18.8
    it 'papel vazio vira Colaborador E sai marcado como exceção' do
      role, exception = described_class.resolve(hierarchy: nil, name: '')
      expect(role).to eq('colaborador')
      expect(exception).to be(true)

      role, exception = described_class.resolve(hierarchy: '', name: nil)
      expect(role).to eq('colaborador')
      expect(exception).to be(true)
    end

    # O exemplo que prova que não há fórmula.
    it 'FALHA ALTO com hierarchy desconhecido — nunca produz nível plausível' do
      expect { described_class.resolve(hierarchy: 950) }
        .to raise_error(Legacy::RoleMap::UnknownLegacyRole, /tabela explícita/)

      expect { described_class.resolve(hierarchy: 1112) }
        .to raise_error(Legacy::RoleMap::UnknownLegacyRole)

      expect { described_class.resolve(name: 'Supervisor') }
        .to raise_error(Legacy::RoleMap::UnknownLegacyRole)
    end

    it 'o de-para é literal: não existe aritmética entre o valor do legado e o nível do ai9' do
      # Se alguém trocar a tabela por fórmula, 950 passaria a "resolver" para
      # algum nível. Este par é o alarme.
      expect(described_class::BY_HIERARCHY).to eq(
        1111 => 'og', 998 => 'admin', 888 => 'gerente', 799 => 'colaborador'
      )
      expect { described_class.resolve(hierarchy: 950) }.to raise_error(Legacy::RoleMap::UnknownLegacyRole)
    end
  end

  describe '.user_type_for' do
    it 'devolve o UserType do ai9 já na escala menor = mais poder' do
      type, exception = described_class.user_type_for(hierarchy: 998)
      expect(type.name).to eq('admin')
      expect(type.hierarchy_level).to eq(2)
      expect(exception).to be(false)
    end

    it 'o OG do legado (1111, o MAIOR) vira o nível 1 do ai9 (o MENOR)' do
      og, = described_class.user_type_for(hierarchy: 1111)
      colab, = described_class.user_type_for(hierarchy: 799)
      expect(og.hierarchy_level).to be < colab.hierarchy_level
    end
  end
end

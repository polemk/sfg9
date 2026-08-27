require 'rails_helper'

RSpec.describe UserType, type: :model do
  describe 'validations' do
    it 'requires name' do
      ut = UserType.new(description: 'Test', hierarchy_level: 1)
      expect(ut.valid?).to be false
      expect(ut.errors[:name]).to be_present
    end

    it 'requires description' do
      ut = UserType.new(name: 'test', hierarchy_level: 1)
      expect(ut.valid?).to be false
      expect(ut.errors[:description]).to be_present
    end

    it 'requires hierarchy_level' do
      ut = UserType.new(name: 'test', description: 'Test')
      expect(ut.valid?).to be false
      expect(ut.errors[:hierarchy_level]).to be_present
    end
  end

  describe 'class methods' do
    before { UserType.seed_default_types! }

    # DEC-41 — a escala é a do ai9: **menor = mais poder**. Os dois lados são
    # verificados: o nível de cada papel E a ordem entre eles. Um teste que só
    # verificasse a existência dos 4 papéis passaria com a escala invertida.
    it 'semeia os 4 papéis do Safegold na escala do ai9' do
      expect(UserType.og.hierarchy_level).to eq(1)
      expect(UserType.admin.hierarchy_level).to eq(2)
      expect(UserType.gerente.hierarchy_level).to eq(3)
      expect(UserType.colaborador.hierarchy_level).to eq(4)
    end

    it 'não recria os tipos removidos pelo DEC-41' do
      expect(UserType.where(name: %w[client free visitor])).to be_empty
      expect(UserType.count).to eq(4)
    end

    it 'é idempotente: rodar duas vezes não duplica' do
      expect { UserType.seed_default_types! }.not_to change(UserType, :count)
    end

    it '.default_type é o Colaborador (DEC-18.8)' do
      expect(UserType.default_type).to eq(UserType.colaborador)
    end

    # O sinal da comparação, nos DOIS lados. `higher_than(3)` tem de devolver
    # quem manda MAIS que o Gerente, não menos.
    it 'higher_than devolve quem tem MAIS poder' do
      names = UserType.higher_than(3).pluck(:name)
      expect(names).to contain_exactly('og', 'admin')
      expect(names).not_to include('colaborador')
    end

    it 'lower_than devolve quem tem MENOS poder' do
      names = UserType.lower_than(3).pluck(:name)
      expect(names).to contain_exactly('colaborador')
      expect(names).not_to include('og')
    end
  end
end

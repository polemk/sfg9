# frozen_string_literal: true

require 'rails_helper'

# S10 / 10.3 — o lançamento mensal (`BE-329`, `DB-311`).
#
# No legado a identidade do lançamento existe **só na aplicação**
# (`validates_uniqueness_of :month, scope: [...]`) e a faixa do mês não existe em
# lugar nenhum: mês 13 passa pela validação e explode depois em
# `Date.new(year, month)`. Aqui as duas coisas estão no banco também.
RSpec.describe IndicatorEntry do
  let(:projeto) { create(:project) }
  let(:indicador) { create(:indicator, title: 'MARGEM') }

  describe 'identidade — (projeto, indicador, ano, mês)' do
    it 'recusa o segundo lançamento do mesmo período na APLICAÇÃO' do
      create(:indicator_entry, project: projeto, indicator: indicador, year: 2024, month: 5)
      duplicado = build(:indicator_entry, project: projeto, indicator: indicador, year: 2024, month: 5)

      expect(duplicado).not_to be_valid
      expect(duplicado.errors[:month]).to be_present
    end

    # A validação de aplicação não protege contra duas abas. Este exemplo prova
    # que o **índice do banco** recusa mesmo quando a validação é contornada —
    # é a corrida que produzia duplicata no legado.
    it 'recusa também no ÍNDICE do banco, contornando a validação' do
      create(:indicator_entry, project: projeto, indicator: indicador, year: 2024, month: 5)
      # `save(validate: false)` pula o `before_validation` que copia a foto do
      # indicador, então os `null: false` são preenchidos à mão aqui: o alvo do
      # exemplo é o ÍNDICE, não a validação.
      duplicado = build(:indicator_entry, project: projeto, indicator: indicador, year: 2024, month: 5,
                                          title: 'MARGEM', value_type: 'Dinheiro')

      expect { duplicado.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'o MESMO mês em outro projeto é aceito' do
      outro = create(:project)
      create(:indicator_entry, project: projeto, indicator: indicador, year: 2024, month: 5)

      expect(build(:indicator_entry, project: outro, indicator: indicador, year: 2024, month: 5)).to be_valid
    end
  end

  describe 'faixa de mês e ano' do
    it 'mês 13 é 422 na aplicação — no legado passava e explodia em `Date.new`' do
      entrada = build(:indicator_entry, project: projeto, indicator: indicador, month: 13)

      expect(entrada).not_to be_valid
      expect(entrada.errors[:month]).to include('precisa estar entre 1 e 12')
    end

    it 'mês 13 é recusado também pelo CHECK do banco' do
      entrada = build(:indicator_entry, project: projeto, indicator: indicador, month: 13,
                                        title: 'MARGEM', value_type: 'Dinheiro')

      expect { entrada.save(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /chk_indicator_entries_month_range/)
    end

    it 'ano 0 é 422 — o outro jeito de estourar o `Date.new(year, month)`' do
      expect(build(:indicator_entry, project: projeto, indicator: indicador, year: 0)).not_to be_valid
    end
  end

  describe 'valor' do
    it 'zero é VÁLIDO — é um lançamento, não ausência' do
      expect(build(:indicator_entry, project: projeto, indicator: indicador, value: 0)).to be_valid
    end

    it '`nil` é inválido' do
      expect(build(:indicator_entry, project: projeto, indicator: indicador, value: nil)).not_to be_valid
    end

    it 'aceita NEGATIVO — replicado (a view do legado pinta a célula de vermelho)' do
      entrada = create(:indicator_entry, project: projeto, indicator: indicador, value: -1_500.75)

      expect(entrada.reload.value).to eq(BigDecimal('-1500.75'))
    end
  end

  describe 'a foto denormalizada' do
    it 'copia título, chave e tipo do indicador na gravação' do
      entrada = create(:indicator_entry, project: projeto, indicator: indicador)

      expect(entrada.title).to eq('MARGEM')
      expect(entrada.key).to eq('margem')
      expect(entrada.value_type).to eq('Dinheiro')
    end

    it 'sem indicador é 422, não `NoMethodError` (o legado fazia `self.indicator.title`)' do
      entrada = build(:indicator_entry, project: projeto, indicator: nil)

      expect { entrada.valid? }.not_to raise_error
      expect(entrada.errors[:indicator]).to be_present
    end
  end

  describe '#beauty_value — o método que o legado escreveu e nunca chamou na grade' do
    it 'formata em BRL' do
      entrada = create(:indicator_entry, project: projeto, indicator: indicador, value: 1_234.5)

      expect(entrada.beauty_value).to eq('R$ 1.234,50')
    end

    it 'entrada sem id devolve "N/A" — a origem da distinção da DEC-70' do
      expect(described_class.new.beauty_value).to eq('N/A')
    end
  end

  describe 'escopo por projeto (C1)' do
    it 'inclui `ProjectScoped` e NÃO usa `default_scope`' do
      expect(described_class).to be_project_scoped
      expect(described_class.all.to_sql).not_to include('project_id')
    end
  end
end

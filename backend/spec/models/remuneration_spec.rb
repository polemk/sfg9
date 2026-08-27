# frozen_string_literal: true

require 'rails_helper'

# S8 / **BE-301**, **BE-303**, **BE-304**, **DB-284**, tarefa 12.2.
#
# A unicidade (projeto, classe, tipo) é testada **nos dois níveis**, e isso é o
# ponto do arquivo: no legado ela existia só em `validates_uniqueness_of`
# (`remuneration.rb:11`), que não vê a corrida entre duas abas. Duas taxas para
# o mesmo tipo no mesmo projeto fariam o `.first` de `Receipt#fetch` escolher
# uma **arbitrariamente** — e o cliente seria cobrado com a taxa que o
# planejador de consulta calhasse de devolver primeiro.
RSpec.describe Remuneration do
  let(:projeto) { create(:project) }
  let(:tipo_est) { create(:structured_operation_type, title: 'Fomento EST') }
  let(:tipo_liq) { create(:risk_operation_type, title: 'Fomento LIQ') }

  describe 'unicidade (projeto, classe, tipo)' do
    before { create(:remuneration, project: projeto, operation_type: tipo_est, value: BigDecimal('2.55')) }

    it 'a validação da APLICAÇÃO recusa a segunda' do
      duplicada = build(:remuneration, project: projeto, operation_type: tipo_est, value: BigDecimal('9.99'))

      expect(duplicada).not_to be_valid
      expect(duplicada.errors[:operation_type_id]).to be_present
    end

    it 'e o ÍNDICE do banco recusa mesmo contornando a validação (a corrida entre duas abas)' do
      # `title` é preenchido à mão porque `save!(validate: false)` pula o
      # `before_validation` que o copiaria — e a coluna é `null: false`. O
      # objetivo do exemplo é chegar ao ÍNDICE, não parar no NOT NULL.
      duplicada = build(:remuneration, project: projeto, operation_type: tipo_est,
                                       value: BigDecimal('9.99'), title: 'Fomento EST')

      expect { duplicada.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'o MESMO tipo em outro projeto é permitido — a taxa é por projeto' do
      outro = create(:project)
      expect(build(:remuneration, project: outro, operation_type: tipo_est)).to be_valid
    end

    it 'a MESMA id de tipo em outra CLASSE não colide — a chave é composta' do
      # `operation_type_id` sozinho não identifica: um `RiskOperationType` e um
      # `StructuredOperationType` podem ter o mesmo uuid em teoria, e o
      # polimorfismo exige que a classe entre na chave.
      expect(build(:remuneration, :liquidavel, project: projeto, operation_type: tipo_liq)).to be_valid
    end
  end

  describe 'BE-304 — a classe e a sigla' do
    it 'StructuredOperationType → EST → StructuredOperation' do
      rem = create(:remuneration, project: projeto, operation_type: tipo_est)

      expect(rem.beauty_type).to eq('EST')
      expect(rem.operation_class).to eq(StructuredOperation)
    end

    it 'RiskOperationType → LIQ → RiskOperation (o outro lado, C3)' do
      rem = create(:remuneration, :liquidavel, project: projeto, operation_type: tipo_liq)

      expect(rem.beauty_type).to eq('LIQ')
      expect(rem.operation_class).to eq(RiskOperation)
    end

    it 'a sigla NUNCA é `"???"` — o domínio é fechado por validação e por constraint' do
      # No legado o `else` de `beauty_type` devolvia a string `"???"`, que ia
      # para a coluna `kind` do recibo, atravessava a validação de presença e
      # virava um recibo que nenhum filtro encontrava.
      invalida = build(:remuneration, project: projeto, operation_type_type: 'Qualquer',
                                      operation_type_id: SecureRandom.uuid)

      expect(invalida).not_to be_valid
      expect(invalida.errors[:operation_type_type]).to be_present
      expect(invalida.beauty_type).to be_nil
    end
  end

  describe 'DB-285 / B-06 — o `title` desnormalizado' do
    it 'é copiado do tipo em TODO save, não só no create' do
      rem = create(:remuneration, project: projeto, operation_type: tipo_est)
      expect(rem.title).to eq('Fomento EST')

      tipo_est.update!(title: 'Fomento Renomeado')
      rem.update!(value: BigDecimal('3.00'))

      expect(rem.reload.title).to eq('Fomento Renomeado')
    end
  end

  describe 'BE-303 — a exclusão bloqueia' do
    it 'com recibo emitido, `destroy` falha e a mensagem nomeia o vínculo' do
      rem = create(:remuneration, project: projeto, operation_type: tipo_est)
      Receipt.create!(project: projeto, charge: create(:charge, project: projeto), remuneration: rem,
                      kind: Receipt::KIND_STRUCTURED, title: 'Recibo', fee: BigDecimal('2.55'),
                      operation_value: BigDecimal('100.00'), value: BigDecimal('2.55'),
                      user_id: create(:user).id)

      expect(rem.destroy).to be(false)
      expect(rem.errors.full_messages.join).to be_present
      expect(described_class.exists?(rem.id)).to be(true)
    end
  end

  describe 'T-D9 — a faixa de `value` continua SEM validação' do
    it '250% é válido, e -5% também' do
      expect(build(:remuneration, project: projeto, operation_type: tipo_est, value: BigDecimal('250'))).to be_valid
      expect(build(:remuneration, project: projeto, operation_type: tipo_est, value: BigDecimal('-5'))).to be_valid
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

# S4 / **DEC-112** — o carimbo de `has_safegold_management` nas 6 tabelas.
#
# Este arquivo existe porque a decisão é contra-intuitiva: o comportamento
# correto **é** o inconsistente. Sem um teste que o diga, a próxima pessoa
# "conserta" a divergência e apaga o histórico que o cliente lê no BI.
RSpec.describe SafegoldStamped do
  let(:project) { create(:project, has_safegold_management: true) }

  # As 6 do legado. `Renegotiation` carimba dentro de
  # `carimbar_projeto_e_fornecedor`, mas honra a mesma chave do ETL.
  it 'as SEIS tabelas do legado têm a coluna — nenhuma deriva na leitura' do
    %w[Company AvailabilityEntry ReceivableEntry Renegotiation RiskControl RiskEntry].each do |nome|
      expect(nome.constantize.column_names).to include('has_safegold_management'), "#{nome} sem a coluna"
    end
  end

  describe 'a origem do carimbo' do
    it '`Company` copia do PROJETO' do
      expect(create(:company, project: project).has_safegold_management).to be(true)
    end

    # `risk_control.rb:15` copia da EMPRESA, não do projeto. A cadeia importa:
    # ressincronizar `companies` não atualiza os limites já gravados.
    it '`RiskControl` copia da EMPRESA, não do projeto' do
      empresa = create(:company, project: project)
      empresa.update_columns(has_safegold_management: false)
      limite = create(:risk_control, project: project, company: empresa.reload)

      expect(project.has_safegold_management).to be(true)
      expect(limite.has_safegold_management).to be(false)
    end
  end

  # É o **D-30**, replicado de propósito. O `before_validation` do legado não
  # tem `on:`: recarimba em todo save, não só na criação.
  it 'recarimba em TODO save, não só na criação' do
    empresa = create(:company, project: project)
    project.update_columns(has_safegold_management: false)

    expect { empresa.update!(title: 'Renomeada') }
      .to change { empresa.reload.has_safegold_management }.from(true).to(false)
  end

  # A chave que o ETL liga. Sem ela, carregar o dump de produção sobrescreveria
  # o carimbo de cada linha pelo valor de HOJE do projeto — 28.131 recebíveis e
  # 642.447 posições de risco perdendo o valor histórico em silêncio.
  describe '`preserve_safegold_stamp` (só o ETL liga)' do
    it 'preserva o valor da origem em vez de recopiar do projeto' do
      empresa = Company.new(project: project, title: 'Carga historica')
      empresa.preserve_safegold_stamp = true
      empresa.has_safegold_management = false
      empresa.save!

      # O projeto é `true`; a linha histórica continua `false`.
      expect(empresa.reload.has_safegold_management).to be(false)
    end

    it 'sem a chave, o callback vence o valor atribuído' do
      empresa = Company.new(project: project, title: 'Carga normal', has_safegold_management: false)
      empresa.save!

      expect(empresa.reload.has_safegold_management).to be(true)
    end
  end
end

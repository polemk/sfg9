# frozen_string_literal: true

require 'rails_helper'

# S5 / BE-269, DEC-57 — a posição diária de risco.
#
# **Sem service, sem endpoint e sem tela.** O que se testa aqui é o dado: as
# derivações e a unicidade. Se algum dia aparecer um endpoint de `risk_entries`,
# ele contraria a DEC-57 e precisa de decisão nova.
RSpec.describe RiskEntry do
  let(:project) { create(:project) }
  let(:company) { create(:company, project: project) }
  let(:control) { create(:risk_control, project: project, company: company) }

  describe 'derived totals override whatever is sent' do
    it 'recomputes the five totals on every save' do
      entry = create(:risk_entry,
                     risk_control: control, company: company, project: project,
                     vencidos_value: 10.00, a_vencer_value: 5.00,
                     liquidacao_value: 3.00, descontos_value: 2.00,
                     comissaria_vencidos_value: 7.00, comissaria_a_vencer_value: 1.00,
                     fomento_vencidos_value: 4.00, fomento_a_vencer_value: 6.00,
                     intercompany_vencidos_value: 8.00, intercompany_a_vencer_value: 2.00,
                     # Valores enviados de propósito ERRADOS: têm de ser sobrepostos.
                     total_carteira_value: 999.00, total_reducoes_value: 999.00,
                     comissaria_total_value: 999.00, fomento_total_value: 999.00,
                     intercompany_total_value: 999.00)

      expect(entry.total_carteira_value).to eq(15.00)
      expect(entry.total_reducoes_value).to eq(5.00)
      expect(entry.comissaria_total_value).to eq(8.00)
      expect(entry.fomento_total_value).to eq(10.00)
      expect(entry.intercompany_total_value).to eq(10.00)
    end

    it 'stamps the project and the control title' do
      entry = create(:risk_entry, risk_control: control, company: company, project: project)
      expect(entry.project_id).to eq(company.project_id)
      expect(entry.risk_control_title).to eq(control.title)
    end
  end

  describe 'uniqueness by (date, control, company)' do
    it 'refuses a second position for the same day' do
      create(:risk_entry, risk_control: control, company: company,
                          project: project, date: Date.new(2026, 3, 31))
      duplicado = build(:risk_entry, risk_control: control, company: company,
                                     project: project, date: Date.new(2026, 3, 31))
      expect(duplicado).not_to be_valid
    end
  end

  describe 'DEC-57 — data yes, surface no' do
    it 'has no service class' do
      expect(defined?(Risk::EntryService)).to be_nil
    end
  end

  describe 'the legacy after_initialize is NOT ported' do
    it 'does not blow up on a bare .new' do
      # No legado `RiskEntry.new` sem empresa levantava `NoMethodError` no
      # `after_initialize` (`risk_entry.rb:25-27`).
      expect { described_class.new }.not_to raise_error
    end
  end
end

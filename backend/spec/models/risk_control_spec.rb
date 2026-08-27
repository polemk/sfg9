# frozen_string_literal: true

require 'rails_helper'

# S5 / BE-239, BE-240 — o limite de risco.
RSpec.describe RiskControl do
  let(:project) { create(:project) }
  let(:company) { create(:company, project: project) }
  let(:carrier) { create(:carrier) }
  let(:tipo) { create(:risk_operation_type) }

  describe 'derivations before validation (BE-239)' do
    it 'copies the carrier title and derives the project from the company' do
      control = create(:risk_control, project: project, company: company, carrier: carrier)
      expect(control.title).to eq(carrier.title)
      expect(control.project_id).to eq(company.project_id)
    end

    it 'rewrites the title on EVERY save, not only on create' do
      control = create(:risk_control, project: project, company: company, carrier: carrier)
      carrier.update!(title: 'Portador Renomeado')
      control.update!(taxa: 9.99)
      expect(control.reload.title).to eq('Portador Renomeado')
    end

    # DEC-112 — carimbo COPIADO DA EMPRESA (`risk_control.rb:15`), em coluna
    # própria, e nunca ressincronizado (D-30).
    it 'stamps has_safegold_management from the COMPANY and never resyncs it' do
      expect(described_class.column_names).to include('has_safegold_management')
      # `update_columns`: um `update!` passaria pelo `before_validation` da
      # própria `Company`, que recopia do projeto e desfaria o arranjo.
      company.update_columns(has_safegold_management: true)
      control = create(:risk_control, project: project, company: company.reload)
      expect(control.has_safegold_management).to be(true)

      company.update_columns(has_safegold_management: false)
      expect(control.reload.has_safegold_management).to be(true)
    end

    it 'is INVALID (not a crash) when the company is missing' do
      # No legado `self.company.project_id` levantava `NoMethodError` antes de a
      # validação rodar, e o endpoint devolvia 500 onde deveria devolver 422.
      control = described_class.new(carrier: carrier, risk_operation_type: tipo, limite: 1, taxa: 1)
      expect { control.valid? }.not_to raise_error
      expect(control).not_to be_valid
      expect(control.errors[:company_id]).to be_present
    end
  end

  describe 'validations (BE-240)' do
    it 'refuses a duplicate (company, carrier, type) in the application' do
      create(:risk_control, project: project, company: company, carrier: carrier, risk_operation_type: tipo)
      duplicado = build(:risk_control, project: project, company: company,
                                       carrier: carrier, risk_operation_type: tipo)
      expect(duplicado).not_to be_valid
    end

    it 'refuses a duplicate at the DATABASE level too — the index closes the race' do
      create(:risk_control, project: project, company: company, carrier: carrier, risk_operation_type: tipo)
      expect do
        described_class.insert_all!([{
                                      project_id: project.id, company_id: company.id,
                                      carrier_id: carrier.id, risk_operation_type_id: tipo.id,
                                      limite: 1, taxa: 1, is_active: true,
                                      created_at: Time.current, updated_at: Time.current
                                    }])
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'ACCEPTS limite zero — it keeps the protected-division branch alive' do
      control = build(:risk_control, project: project, company: company,
                                     carrier: carrier, risk_operation_type: tipo, limite: 0)
      expect(control).to be_valid
    end
  end

  describe 'the two divergent readings of deactivation (B-02)' do
    it 'keeps #operations blind to is_active, on purpose' do
      control = create(:risk_control, project: project, company: company)
      operacao = create(:risk_operation, risk_control: control)
      control.deactivate!

      expect(control.reload.is_active).to be(false)
      expect(control.operations).to include(operacao)
      expect(described_class.active).not_to include(control)
    end
  end

  describe 'deletion blocks, never cascades (D-24 / BE-238)' do
    it 'refuses to delete a control that has an operation' do
      control = create(:risk_control, project: project, company: company)
      create(:risk_operation, risk_control: control)

      expect(control.destroy).to be(false)
      expect(control.errors.full_messages.join).to match(/operação\(ões\) de risco/i)
      expect(described_class.exists?(control.id)).to be(true)
    end

    it 'refuses to delete a control that has a daily position' do
      control = create(:risk_control, project: project, company: company)
      create(:risk_entry, risk_control: control, company: company, project: project)

      expect(control.destroy).to be(false)
      expect(described_class.exists?(control.id)).to be(true)
    end
  end

  describe 'search — IMP-R3' do
    it 'actually filters, which the legacy `q` never did' do
      alvo = create(:risk_control, project: project, company: company,
                                   carrier: create(:carrier, title: 'Banco Alfa'))
      outro = create(:risk_control, project: project, company: company,
                                    carrier: create(:carrier, title: 'Banco Beta'))

      resultado = described_class.for_project(project).search('alfa')
      expect(resultado).to include(alvo)
      expect(resultado).not_to include(outro)
    end

    it 'treats % and _ as TEXT, not as SQL wildcards' do
      create(:risk_control, project: project, company: company,
                            carrier: create(:carrier, title: 'Banco Gama'))
      expect(described_class.for_project(project).search('%')).to be_empty
    end
  end

  describe 'contract C1' do
    it 'is project scoped and never a global catalog' do
      expect(described_class).to be_project_scoped
      expect(described_class).not_to respond_to(:global_catalog?)
    end

    it 'has no default_scope' do
      expect(described_class.default_scopes).to be_empty
    end
  end
end

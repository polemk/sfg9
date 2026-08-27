# frozen_string_literal: true

require 'rails_helper'

# **DEC-127** — decisão registrada não é decisão implementada.
#
# Cinco decisões assinadas (DEC-119 ×3, DEC-125, DEC-128.4) mandaram tornar
# PARCIAIS cinco unicidades. Cada uma exige **duas** mudanças — a migration
# `20260827020000_unicidade_parcial_onde_o_legado_diz_nao_se_aplica` e a
# validação do model — e a lição que custou o dia da DEC-127 é que fazer só uma
# **parece** resolvido: com o índice parcial e a validação intacta, a carga ainda
# parava em `Integration key já está em uso neste projeto`.
#
# Por isso **todo exemplo aqui prova as DUAS DIREÇÕES**:
#
#   1. o valor de "não se aplica" **repete** sem ser recusado — pelo model E pelo
#      banco (`save!(validate: false)`, que passa por cima da validação e cai
#      direto no índice);
#   2. a duplicata **de verdade** continua recusada — pelo model E pelo banco.
#
# Provar só (1) é como assinar a chave no `decisions.yml`: destrava a carga e
# apaga a restrição. Provar só (2) é o estado anterior a esta migration.
RSpec.describe 'Unicidade parcial onde o legado diz "não se aplica"' do
  # O banco é a trava; a validação do model é a mensagem. Este auxiliar pula a
  # validação de propósito para chegar ao índice.
  def gravar_sem_validar(record)
    # `validate` roda os `before_validation` que DERIVAM colunas obrigatórias
    # (`integration_key` a partir do título, `provider_name` a partir do
    # fornecedor). O resultado é descartado de propósito: o que este auxiliar
    # quer provar é o que o **índice** faz, não o que a validação diz.
    record.validate
    record.save!(validate: false)
  end

  # ==========================================================================
  # DEC-119 §1 — `carriers.bank_code`: sentinela é "sem código bancário"
  # ==========================================================================
  describe 'carriers.bank_code (DEC-119)' do
    Carrier::SENTINELAS_SEM_BANCO.each do |sentinela|
      it "aceita o sentinela #{sentinela} repetido — no model e no banco" do
        create(:carrier, bank_code: sentinela)
        segundo = build(:carrier, bank_code: sentinela)

        expect(segundo).to be_valid
        expect { gravar_sem_validar(segundo) }.not_to raise_error
      end
    end

    it 'aceita NULL repetido' do
      create(:carrier, bank_code: nil)
      expect(build(:carrier, bank_code: nil)).to be_valid
      expect { gravar_sem_validar(build(:carrier, bank_code: nil)) }.not_to raise_error
    end

    it 'RECUSA código bancário de verdade repetido — no model' do
      create(:carrier, bank_code: '001')
      segundo = build(:carrier, bank_code: '001')

      expect(segundo).not_to be_valid
      expect(segundo.errors[:bank_code]).to include('já está em uso por outro portador')
    end

    it 'RECUSA código bancário de verdade repetido — no banco, mesmo sem validação' do
      create(:carrier, bank_code: '001')

      expect { gravar_sem_validar(build(:carrier, bank_code: '001')) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'não confunde o sentinela com o código de verdade' do
      create(:carrier, bank_code: '8888')
      expect(build(:carrier, bank_code: '888')).to be_valid
      expect(build(:carrier, bank_code: '088')).to be_valid
    end
  end

  # ==========================================================================
  # DEC-119 §2 — `users.username`: 72 contas com o campo vazio
  # ==========================================================================
  describe 'users.username (DEC-119)' do
    it 'aceita `username` vazio repetido — no model e no banco' do
      create(:user, username: '')
      segundo = build(:user, username: '')

      expect(segundo).to be_valid
      expect { gravar_sem_validar(segundo) }.not_to raise_error
    end

    it 'aceita `username` nulo repetido' do
      create(:user, username: nil)
      expect { gravar_sem_validar(build(:user, username: nil)) }.not_to raise_error
    end

    it 'RECUSA `username` preenchido repetido — no model' do
      create(:user, username: 'joana.silva')
      segundo = build(:user, username: 'joana.silva')

      expect(segundo).not_to be_valid
      expect(segundo.errors[:username]).to be_present
    end

    it 'RECUSA `username` preenchido repetido — no banco, mesmo sem validação' do
      create(:user, username: 'joana.silva')

      expect { gravar_sem_validar(build(:user, username: 'joana.silva')) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  # ==========================================================================
  # DEC-125 — `providers[project_id + integration_key]`: 163 de 289 linhas
  # ==========================================================================
  describe 'providers[project_id + integration_key] (DEC-125)' do
    let(:project) { create(:project) }

    it 'aceita a chave repetida entre linhas HERDADAS — no model e no banco' do
      create(:provider, project: project, integration_key: 'SSA', legacy_id: 1)
      segundo = build(:provider, project: project, integration_key: 'SSA', legacy_id: 2)

      expect(segundo).to be_valid
      expect { gravar_sem_validar(segundo) }.not_to raise_error
    end

    it 'aceita a chave herdada repetida ainda que o rótulo seja o mesmo do outro caso decidido' do
      # Um dos 6 grupos usa literalmente `Renegociação`, o rótulo já decidido em
      # `renegotiations` pela DEC-119.
      create(:provider, project: project, integration_key: 'Renegociação', legacy_id: 10)
      expect { gravar_sem_validar(build(:provider, project: project, integration_key: 'Renegociação', legacy_id: 11)) }
        .not_to raise_error
    end

    it 'RECUSA a chave repetida entre linhas NASCIDAS NO ai9 — no model' do
      create(:provider, project: project, integration_key: 'ssa')
      segundo = build(:provider, project: project, integration_key: 'ssa')

      expect(segundo).not_to be_valid
      expect(segundo.errors[:integration_key]).to include('já está em uso neste projeto')
    end

    it 'RECUSA a chave repetida entre linhas nascidas no ai9 — no banco, mesmo sem validação' do
      create(:provider, project: project, integration_key: 'ssa')

      expect { gravar_sem_validar(build(:provider, project: project, integration_key: 'ssa')) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'continua permitindo a mesma chave em projetos DIFERENTES (C1)' do
      create(:provider, project: project, integration_key: 'ssa')
      expect(build(:provider, project: create(:project), integration_key: 'ssa')).to be_valid
    end
  end

  # ==========================================================================
  # DEC-119 §"renegotiations" — a chave sai de `provider_name`, e um fornecedor
  # tem várias renegociações no mesmo projeto
  # ==========================================================================
  describe 'renegotiations[project_id + integration_key] (DEC-119)' do
    let(:project) { create(:project) }
    let(:fornecedor) { create(:provider, project: project) }
    let(:empresa) { create(:company, project: project) }

    # `build` não persiste as associações da factory, e `provider_id`/`company_id`
    # são `null: false`: sem estas duas, o exemplo morre na FK antes de chegar ao
    # índice que ele quer medir.
    def nova_renegociacao(**atributos)
      build(:renegotiation, project: project, provider: fornecedor, company: empresa, **atributos)
    end

    it 'aceita a chave repetida entre linhas HERDADAS — no model e no banco' do
      nova_renegociacao(integration_key: 'Renegociação', legacy_id: 1).save!
      segundo = nova_renegociacao(integration_key: 'Renegociação', legacy_id: 2)

      expect(segundo).to be_valid
      expect { gravar_sem_validar(segundo) }.not_to raise_error
    end

    it 'aceita repetida a chave DERIVADA de um mesmo fornecedor (banco_bradesco)' do
      nova_renegociacao(integration_key: 'banco_bradesco', legacy_id: 3).save!
      expect { gravar_sem_validar(nova_renegociacao(integration_key: 'banco_bradesco', legacy_id: 4)) }
        .not_to raise_error
    end

    it 'RECUSA a chave repetida entre linhas NASCIDAS NO ai9 — no model' do
      nova_renegociacao(integration_key: 'banco_bradesco').save!
      segundo = nova_renegociacao(integration_key: 'banco_bradesco')

      expect(segundo).not_to be_valid
      expect(segundo.errors[:integration_key]).to include('já está em uso neste projeto')
    end

    it 'RECUSA a chave repetida entre linhas nascidas no ai9 — no banco, mesmo sem validação' do
      nova_renegociacao(integration_key: 'banco_bradesco').save!

      expect { gravar_sem_validar(nova_renegociacao(integration_key: 'banco_bradesco')) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  # ==========================================================================
  # DEC-128.4 — `availability_templates`: 90 de 2.705 com título vazio
  # ==========================================================================
  describe 'availability_templates[… + title] (DEC-128.4)' do
    let(:project) { create(:project) }

    it 'aceita título VAZIO repetido na raiz — no model e no banco' do
      create(:project_availability_template, project: project, title: '', legacy_id: 1)
      segundo = build(:project_availability_template, project: project, title: '', legacy_id: 2)

      expect(segundo).to be_valid
      expect { gravar_sem_validar(segundo) }.not_to raise_error
    end

    it 'aceita título VAZIO repetido entre filhos do mesmo pai' do
      pai = create(:project_availability_template, project: project)
      create(:project_availability_template, project: project, parent_template: pai, title: '', legacy_id: 3)

      expect { gravar_sem_validar(build(:project_availability_template, project: project,
                                                                       parent_template: pai, title: '',
                                                                       legacy_id: 4)) }
        .not_to raise_error
    end

    it 'RECUSA título vazio em padrão NASCIDO NO ai9 (sem `legacy_id`) — a exigência continua de pé' do
      novo = build(:project_availability_template, project: project, title: '')

      expect(novo).not_to be_valid
      expect(novo.errors[:title]).to be_present
    end

    it 'RECUSA título PREENCHIDO repetido na raiz — no banco, mesmo sem validação' do
      create(:project_availability_template, project: project, title: 'Caixa', legacy_id: 5)

      expect { gravar_sem_validar(build(:project_availability_template, project: project,
                                                                       title: 'Caixa', legacy_id: 6)) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'RECUSA título preenchido repetido entre filhos do mesmo pai — no banco' do
      pai = create(:project_availability_template, project: project)
      create(:project_availability_template, project: project, parent_template: pai, title: 'Caixa', legacy_id: 7)

      expect { gravar_sem_validar(build(:project_availability_template, project: project, parent_template: pai,
                                                                       title: 'Caixa', legacy_id: 8)) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end

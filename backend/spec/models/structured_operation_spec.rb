# frozen_string_literal: true

require 'rails_helper'

# S8 / **BE-290**…**BE-295**, **DB-297**, tarefa 12.1.
#
# Este arquivo existe para travar **três derivações e quatro ausências**. As
# ausências são a parte que costuma sumir: sem um teste que diga "não existe
# validação de `due_date >= issue_date`, e é de propósito", a primeira pessoa a
# ler o model acrescenta a validação achando que corrige um esquecimento — e
# passa a recusar registro que o sistema aceita há três anos (DEC-30).
RSpec.describe StructuredOperation do
  let(:projeto) { create(:project) }
  let(:empresa) { create(:company, project: projeto) }
  let(:portador) { create(:carrier, title: 'Portador Beta') }
  let(:tipo) { create(:structured_operation_type) }

  # `author` é criado (e não construído) de propósito: `user_id` é
  # `validates presence` e o `build` do FactoryBot construiria um usuário sem
  # id, deixando a coluna nula. É o mesmo cuidado da factory de `RiskOperation`.
  let(:autor) { create(:user) }

  def nova(**extra)
    build(:structured_operation, project: projeto, company: empresa, carrier: portador,
                                 operation_type: tipo, author: autor, **extra)
  end

  # ====================================================================
  # As três derivações do `before_validation`
  # ====================================================================
  describe 'derivações' do
    it '1) `title` em branco recebe `carrier.title` — SÓ no create' do
      op = nova(title: nil)
      op.save!
      expect(op.title).to eq('Portador Beta')

      # Renomear o portador DEPOIS não mexe no título: é fotografia, não
      # referência (`structured_operation.rb:31-33`, `on: [:create]`).
      portador.update!(title: 'Portador Renomeado')
      op.update!(observation: 'toque')
      expect(op.reload.title).to eq('Portador Beta')
    end

    it '1b) BE-290 — portador inexistente devolve erro de validação, não `NoMethodError`' do
      # No legado a derivação faz `self.carrier.title` ANTES de qualquer
      # validação: com um id que não existe, o callback levanta `NoMethodError`
      # em `nil` e a validação de presença — que existe e daria a mensagem
      # amigável — **nunca chega a rodar**.
      op = nova(title: nil)
      op.carrier = nil
      expect { op.valid? }.not_to raise_error
      expect(op.errors[:carrier_id]).to be_present
    end

    it '2) `project_id` vem da EMPRESA em todo save, sobrescrevendo o que veio no objeto' do
      outro = create(:project)
      op = nova
      op.project_id = outro.id
      op.save!

      expect(op.project_id).to eq(empresa.project_id)
    end

    it '3) DEC-01 — `original_balance` é gravado NEGATIVO, sempre' do
      op = nova(original_balance: BigDecimal('50000.00'))
      op.save!
      expect(op.original_balance).to eq(BigDecimal('-50000.00'))

      ja_negativo = nova(original_balance: BigDecimal('-777.00'))
      ja_negativo.save!
      expect(ja_negativo.original_balance).to eq(BigDecimal('-777.00'))
    end
  end

  # ====================================================================
  # Golden E6 — o `balance` DECORATIVO (T-D6 / BE-292)
  # ====================================================================
  # ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b / DEC-115 · fonte:
  # `../sfg/app/models/structured_operation.rb:31-33` (o reset em todo save) e
  # `../sfg/db/migrate/20220701125757_create_structured_operations.rb:11`.
  # `structured_operations` está entre as 24 migrations que nunca subiram: este
  # golden tem **fonte, não oráculo**, e não promove nada a `verified`.
  describe 'golden E6 — o `balance` é resetado em TODO save' do
    it 'editar SÓ a observação devolve o saldo corrente ao inicial' do
      op = nova(original_balance: BigDecimal('50000.00'))
      op.save!
      op.update_column(:balance, BigDecimal('-12.34'))

      op.update!(observation: 'só um comentário')

      expect(op.reload.balance).to eq(BigDecimal('-50000.00'))
    end

    it 'e NADA no sistema dá baixa nesse saldo — a coluna é decorativa' do
      # A varredura do legado inteiro não achou nenhum caminho de movimento,
      # liquidação ou baixa de operação estruturada (diferente de
      # `RiskOperation`, que tem `RiskMovement`). Este exemplo trava a
      # constatação: se alguém criar o caminho, ele quebra e a decisão T-D6
      # volta à mesa em vez de ser contornada em silêncio.
      expect(described_class.reflect_on_all_associations.map(&:name))
        .not_to include(:movements, :structured_movements, :settlements)
      expect(described_class.instance_methods).not_to include(:settle!, :apply_movement!)
    end
  end

  # ====================================================================
  # BE-293 — as AUSÊNCIAS de validação são replicadas
  # ====================================================================
  describe 'validações — presenças e, sobretudo, AUSÊNCIAS (BE-293)' do
    it 'exige empresa, projeto, portador, tipo, autor, emissão e vencimento' do
      op = described_class.new
      op.valid?

      %i[company_id project_id carrier_id operation_type_id user_id issue_date due_date]
        .each { |campo| expect(op.errors[campo]).to be_present, "faltou validar #{campo}" }
    end

    it 'a validação de `operation_value` é DEAD CODE — e é dead code no legado também' do
      # `validates :operation_value, presence: true` existe
      # (`structured_operation.rb:19`) e **nunca dispara**: a coluna nasce
      # `default: 0` na migration de 2022
      # (`20220701125757_create_structured_operations.rb:11`), então um registro
      # novo já chega com `0` e a presença passa.
      #
      # O ai9 replica os dois lados — a validação E o default —, e este exemplo
      # existe para que a inutilidade fique registrada em vez de alguém
      # "descobrir" que o capital pode ser zero e achar que a migração perdeu
      # uma regra. Não perdeu: a regra nunca existiu de fato.
      op = described_class.new
      op.valid?

      expect(op.operation_value).to eq(0)
      expect(op.errors[:operation_value]).to be_empty
    end

    it 'NÃO valida `due_date >= issue_date` — ausência replicada' do
      expect(nova(issue_date: Date.new(2026, 12, 1), due_date: Date.new(2026, 1, 1))).to be_valid
    end

    it 'NÃO valida `operation_value > 0` — ausência replicada' do
      expect(nova(operation_value: BigDecimal('-5000.00'))).to be_valid
    end

    it 'NÃO valida a faixa de `agreed_rate` — ausência replicada' do
      expect(nova(agreed_rate: BigDecimal('250.00'))).to be_valid
    end

    it 'NÃO exige `contract_number` único — ausência replicada (Q-R7)' do
      nova(contract_number: 'CT-999').save!
      expect(nova(contract_number: 'CT-999')).to be_valid
    end
  end

  # ====================================================================
  # BE-295 — três colunas SEM consumidor, e o teste que documenta isso
  # ====================================================================
  describe 'as três colunas sem consumidor (BE-295, Q-R14, Q-R18)' do
    it '`agreed_rate`, `is_on_variable` e `is_ended` são persistidas e exibidas, e nada as lê' do
      op = nova(agreed_rate: BigDecimal('7.77'), is_on_variable: true, is_ended: true)
      op.save!

      expect(op.reload.agreed_rate).to eq(BigDecimal('7.77'))
      expect(op.is_on_variable).to be(true)
      expect(op.is_ended).to be(true)

      # Nenhuma das três entra em scope, filtro ou ordenação do model. Se
      # alguém acrescentar um consumidor, este exemplo quebra e a Q-R14 volta à
      # mesa — em vez de a coluna ganhar significado por acidente.
      sqls = [described_class.available_for_receipt.to_sql,
              described_class.search('x').to_sql,
              described_class.in_period(Date.new(2026, 1, 1), Date.new(2026, 12, 31)).to_sql]

      sqls.each do |sql|
        expect(sql).not_to include('agreed_rate')
        expect(sql).not_to include('is_on_variable')
        expect(sql).not_to include('is_ended')
      end

      # E `agreed_rate` **não** é a taxa que remunera: quem remunera é
      # `remunerations.value`. A allowlist de ordenação a oferece (é coluna da
      # tela), mas nenhum cálculo a lê.
      expect(described_class::ORDERING.allowed).to have_key('agreed_rate')
    end

    it 'Q-R18 — operação ENCERRADA continua em `available_for_receipt`' do
      encerrada = nova(is_ended: true)
      encerrada.save!

      expect(described_class.available_for_receipt).to include(encerrada)
    end

    it 'BE-294 — quem sai de `available_for_receipt` é quem tem `receipt_id`' do
      op = nova
      op.save!
      expect(described_class.available_for_receipt).to include(op)

      recibo = Receipt.create!(project: projeto, charge: create(:charge, project: projeto),
                               operation: op,
                               remuneration: create(:remuneration, project: projeto, operation_type: tipo),
                               kind: Receipt::KIND_STRUCTURED, title: 'Recibo',
                               fee: BigDecimal('2.55'), operation_value: op.operation_value,
                               value: BigDecimal('1.00'), user_id: autor.id)
      op.update_column(:receipt_id, recibo.id)

      expect(described_class.available_for_receipt).not_to include(op)
    end

    it 'DB-282 — `receipt_id` tem FK REAL: recibo inexistente é recusado pelo BANCO' do
      # No legado não havia FK nenhuma nas 5 tabelas da unidade, e a coluna
      # podia apontar para o vazio: operação "já faturada" por um recibo que
      # não existe, invisível na lista de candidatos e impossível de faturar.
      op = nova
      op.save!

      expect { op.update_column(:receipt_id, SecureRandom.uuid) }
        .to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  # ====================================================================
  # DB-297 — autor e último editor
  # ====================================================================
  describe 'DB-297 — autor e último editor são colunas SEPARADAS' do
    it 'as duas associações existem e apontam para `User` por colunas diferentes' do
      expect(described_class.reflect_on_association(:author).foreign_key).to eq('user_id')
      expect(described_class.reflect_on_association(:editor).foreign_key).to eq('updated_by_id')
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# S4 / OPS-055, OPS-089 — as duas rotinas de correção de dado.
#
# São testadas porque a coisa que elas fecham é justamente "alguém rodou algo no
# console de produção e ninguém sabe o quê". Uma rotina de correção sem teste é
# a mesma coisa com outro nome.
RSpec.describe 'sfg: rotinas de correção de dado', type: :task do
  # `load_tasks` UMA vez para o processo inteiro. `Rake::Task.clear` seguido de
  # recarga apagaria as tarefas que outro spec já tenha carregado — e o efeito
  # aparece só quando a suíte roda inteira, na ordem errada.
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?('sfg:fix_company_links') }

  before do
    UserType.seed_default_types!
    ENV.delete('APPLY')
  end

  after { ENV.delete('APPLY') }

  let(:dono) { create(:user, user_type: UserType.gerente) }

  def rodar(tarefa, aplicar: false)
    if aplicar
      ENV['APPLY'] = '1'
    else
      ENV.delete('APPLY')
    end
    Rake::Task[tarefa].reenable
    # A rotina imprime o relatório; o teste não precisa do ruído no terminal.
    expect { Rake::Task[tarefa].invoke }.to output.to_stdout
  end

  describe 'sfg:fix_company_links' do
    # A regra 1: rodar sem argumento **não altera nada**.
    it 'em PRÉ-VISUALIZAÇÃO não cria nada' do
      create(:project, owner: dono)
      expect { rodar('sfg:fix_company_links') }.not_to change(Company, :count)
    end

    it 'com APPLY=1 cria a "Empresa Padrão" no projeto que não tem nenhuma' do
      projeto = create(:project, owner: dono)
      rodar('sfg:fix_company_links', aplicar: true)
      expect(Company.for_project(projeto).pluck(:title)).to eq(['Empresa Padrão'])
    end

    it 'é IDEMPOTENTE: a segunda execução não cria uma segunda empresa padrão' do
      projeto = create(:project, owner: dono)
      rodar('sfg:fix_company_links', aplicar: true)
      expect { rodar('sfg:fix_company_links', aplicar: true) }.not_to change(Company, :count)
      expect(Company.for_project(projeto).count).to eq(1)
    end

    it 'normaliza título com espaço sobrando — a causa de "Alfa " e "Alfa" conviverem' do
      projeto = create(:project, owner: dono)
      empresa = create(:company, project: projeto, title: 'Alfa')
      empresa.update_column(:title, '  Alfa  ')

      rodar('sfg:fix_company_links', aplicar: true)
      expect(empresa.reload.title).to eq('Alfa')
    end
  end

  describe 'sfg:fix_project_data' do
    it 'em PRÉ-VISUALIZAÇÃO não altera nada' do
      projeto = create(:project, owner: dono)
      projeto.update_column(:address_state, 'sc')

      rodar('sfg:fix_project_data')
      expect(projeto.reload.address_state).to eq('sc')
    end

    it 'com APPLY=1 normaliza UF, CEP e chave de integração ausente' do
      projeto = create(:project, owner: dono, name: 'Projeto Fora de Forma')
      projeto.update_columns(address_state: 'sc', cep: '89219500', integration_key: nil)

      rodar('sfg:fix_project_data', aplicar: true)

      projeto.reload
      expect(projeto.address_state).to eq('SC')
      expect(projeto.cep).to eq('89219-500')
      expect(projeto.integration_key).to eq('projeto_fora_de_forma')
    end

    it 'é IDEMPOTENTE: a segunda execução não muda mais nada' do
      projeto = create(:project, owner: dono)
      projeto.update_columns(address_state: 'sc', cep: '89219500')

      rodar('sfg:fix_project_data', aplicar: true)
      antes = projeto.reload.updated_at

      rodar('sfg:fix_project_data', aplicar: true)
      expect(projeto.reload.updated_at).to eq(antes)
    end

    # A regra 2: a correção passa pelo MODEL, então a trilha registra. O legado
    # usava `update_all`, que não passa por validação nem por callback.
    it 'a correção passa pelo model e deixa versão na trilha (`paper_trail`)' do
      projeto = create(:project, owner: dono)
      projeto.update_column(:address_state, 'sc')
      versoes_antes = PaperTrail::Version.where(item_type: 'Project', item_id: projeto.id).count

      rodar('sfg:fix_project_data', aplicar: true)

      expect(PaperTrail::Version.where(item_type: 'Project', item_id: projeto.id).count)
        .to be > versoes_antes
    end
  end
end

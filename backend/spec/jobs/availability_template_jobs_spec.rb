# frozen_string_literal: true

require 'rails_helper'

# S11 / BE-113..115, BE-144..147, OPS-082..084, OPS-120..124 — **os jobs de
# padrão de disponibilidade**.
#
# O exemplo central é o primeiro: **força a exceção dentro de cada um dos quatro
# jobs e confere que o padrão fica desbloqueado**. É o teste que fecha o
# **D-05** — no legado o `unlocked!` era a penúltima linha do caminho feliz (e,
# na remoção, não existia), então uma falha deixava o padrão **bloqueado para
# sempre**, sem caminho de recuperação pela interface.
RSpec.describe 'Jobs de padrão de disponibilidade' do
  # O adapter de teste desta base é `:inline` — `perform_later` executa na hora.
  # Para afirmar "**nenhum job entrou na fila**" (que é a metade do D-04/D-33
  # que importa: a guarda roda ANTES de enfileirar) o espião no `perform_later`
  # é mais direto e não muda o adapter para o resto da suíte.
  before do
    [ActivateProjectTemplateJob, DeactivateProjectTemplateJob, RemoveProjectTemplateJob].each do |job|
      allow(job).to receive(:perform_later).and_call_original
    end
  end

  def espera_fila_vazia
    expect(ActivateProjectTemplateJob).not_to have_received(:perform_later)
    expect(DeactivateProjectTemplateJob).not_to have_received(:perform_later)
    expect(RemoveProjectTemplateJob).not_to have_received(:perform_later)
  end

  let(:project) { create(:project) }
  let!(:company) { create(:company, project: project) }
  let(:actor) { create(:user) }

  def padrao(**atributos)
    create(:project_availability_template, project: project, **atributos)
  end

  def lancar(template, valor, em: Date.new(2026, 8, 14))
    Availability::EntryService.create(
      project: project,
      attrs: { availability_template_id: template.id, company_id: company.id, date: em, value: valor }
    ).fetch(:data)
  end

  # -------------------------------------------------------------------
  describe 'D-05 — o bloqueio termina junto com a operação, com ou sem sucesso' do
    # Os quatro jobs, com o método que cada um usa para "fazer o trabalho".
    # Estubar esse método com `raise` é o jeito de forçar a falha sem depender
    # de dado malformado.
    [
      [ActivateProjectTemplateJob, :recalcular_lancamentos],
      [DeactivateProjectTemplateJob, :recalcular_afetados]
    ].each do |classe_do_job, metodo|
      it "#{classe_do_job.name}: exceção no meio deixa o padrão UTILIZÁVEL" do
        alvo = padrao
        alvo.lock!('Operação em andamento.', actor: actor)
        expect(alvo.reload).to be_locked

        allow_any_instance_of(classe_do_job).to receive(metodo).and_raise(StandardError, 'falha forçada')

        expect { classe_do_job.perform_now(alvo.id, actor.id) }.to raise_error(StandardError, 'falha forçada')

        alvo.reload
        expect(alvo).not_to be_locked
        expect(alvo.locked_message).to be_nil
        expect(alvo.job_state).to eq('failed')
      end
    end

    it 'o relatório da falha é `jsonb` ESTRUTURADO — o legado gravava array Ruby em texto livre' do
      alvo = padrao
      alvo.lock!('Operação em andamento.', actor: actor)
      allow_any_instance_of(ActivateProjectTemplateJob).to receive(:recalcular_lancamentos)
        .and_raise(ArgumentError, 'estourou')

      expect { ActivateProjectTemplateJob.perform_now(alvo.id, actor.id) }.to raise_error(ArgumentError)

      relatorio = alvo.reload.job_report
      expect(relatorio['state']).to eq('failed')
      expect(relatorio['error_class']).to eq('ArgumentError')
      expect(relatorio['error_message']).to eq('estourou')
    end

    # A remoção é o caso diferente, e é o **pior** do legado: lá o `unlocked!`
    # não era chamado NUNCA. Aqui não há o que desbloquear quando a remoção
    # já aconteceu — o que se confere é que não sobra um padrão **bloqueado**
    # órfão, nem meia subárvore.
    it 'RemoveProjectTemplateJob: exceção depois do destroy não deixa padrão bloqueado para trás' do
      raiz = padrao
      filho = padrao(parent_template_id: raiz.id)
      raiz.lock!('Removendo.', actor: actor)

      allow_any_instance_of(RemoveProjectTemplateJob).to receive(:recalcular_afetados)
        .and_raise(StandardError, 'falha forçada')

      expect { RemoveProjectTemplateJob.perform_now(raiz.id, actor.id) }
        .to raise_error(StandardError, 'falha forçada')

      expect(ProjectAvailabilityTemplate.where(id: [raiz.id, filho.id])).to be_empty
      expect(ProjectAvailabilityTemplate.for_project(project).where(is_locked: true)).to be_empty
    end

    # S13 / OPS-466 — **este exemplo mudou de sujeito junto com a arquitetura.**
    #
    # A propagação deixou de ser um job só com o laço dentro e passou a ser
    # coordenador + um filho por projeto (`PropagateGlobalTemplateToProjectJob`).
    # Quem falha agora é o **filho**, e é nele que a garantia do D-05 tem de
    # valer: publica `failed` no canal daquele projeto e **relança**, para o
    # Sidekiq retentar só ele. O fechamento do relatório do coordenador é
    # coberto logo abaixo, pelo caminho do `after_discard`.
    it 'PropagateGlobalTemplateToProjectJob: a falha publica `failed` no projeto e SOBE' do
      global = create(:global_availability_template)
      allow(Availability::GlobalSeeder).to receive(:insert_into_project!).and_raise(StandardError, 'x')

      expect do
        expect { PropagateGlobalTemplateToProjectJob.perform_now(global.id, project.id) }
          .to raise_error(StandardError)
      end.to have_broadcasted_to(ProjectProgressChannel.stream_name_for(project.id))
        .with(hash_including(status: 'failed'))
    end

    # O relatório do coordenador **fecha** quando o último filho termina — mesmo
    # que ele termine morrendo. Sem isto o global ficaria `running` para sempre,
    # que é o `job_state` eterno do legado (D-05) reaparecendo de outra forma.
    it 'PropagateGlobalTemplateJob: filho que DESISTE fecha o relatório como `failed`' do
      global = create(:global_availability_template)
      # O adapter desta suíte é `:inline`; sem este espião o filho rodaria na
      # hora e o exemplo mediria o caminho feliz.
      allow(PropagateGlobalTemplateToProjectJob).to receive(:perform_later)
      PropagateGlobalTemplateJob.perform_now(global.id)
      expect(global.reload.job_state).to eq('running')

      PropagateGlobalTemplateJob.register_outcome!(global.id, project.id, 'failed')

      expect(global.reload.job_state).to eq('failed')
      expect(global.job_report['failed']).to eq(1)
      expect(global.job_progress).to eq(100)
    end

    it 'a exceção SOBE — sem `raise` o Sidekiq marcaria sucesso e nada seria retentado (D-79)' do
      alvo = padrao
      allow_any_instance_of(ActivateProjectTemplateJob).to receive(:recalcular_lancamentos)
        .and_raise(StandardError, 'x')

      expect { ActivateProjectTemplateJob.perform_now(alvo.id) }.to raise_error(StandardError)
    end
  end

  # -------------------------------------------------------------------
  describe 'ativação (BE-144 / DC-33)' do
    it 'ativa a subárvore e os ancestrais' do
      raiz = padrao(is_active: false)
      filho = padrao(parent_template_id: raiz.id, is_active: false)

      ActivateProjectTemplateJob.perform_now(filho.id, actor.id)

      expect(raiz.reload).to be_is_active
      expect(filho.reload).to be_is_active
    end

    it 'a segunda ativação responde 409 — não um segundo job' do
      alvo = padrao(is_active: true)

      resultado = Availability::ProjectTemplateService.activate(project: project, id: alvo.id, actor: actor)

      expect(resultado[:status]).to eq(409)
      espera_fila_vazia
    end

    it 'ativar padrão com PAI INATIVO é recusado com orientação (422)' do
      raiz = padrao(is_active: false)
      filho = padrao(parent_template_id: raiz.id, is_active: false)

      resultado = Availability::ProjectTemplateService.activate(project: project, id: filho.id, actor: actor)

      expect(resultado[:status]).to eq(422)
      expect(resultado[:error]).to include(raiz.title)
      espera_fila_vazia
    end

    it 'OPS-122 — a ativação NÃO desliga o logger global do worker' do
      alvo = padrao(is_active: false)
      logger_antes = ActiveRecord::Base.logger

      ActivateProjectTemplateJob.perform_now(alvo.id, actor.id)
      expect(ActiveRecord::Base.logger).to equal(logger_antes)

      # E nem quando falha — que é exatamente o caso em que o legado deixava o
      # logger nulo para o worker inteiro (a restauração ficava DENTRO do bloco).
      allow_any_instance_of(ActivateProjectTemplateJob).to receive(:recalcular_lancamentos).and_raise('x')
      expect { ActivateProjectTemplateJob.perform_now(alvo.id) }.to raise_error(StandardError)
      expect(ActiveRecord::Base.logger).to equal(logger_antes)
    end
  end

  # -------------------------------------------------------------------
  describe 'desativação (BE-145 / D-04 / D-33)' do
    it 'padrão OBRIGATÓRIO é recusado NO SERVIÇO — nenhum job entra na fila' do
      alvo = padrao(is_mandatory: true)

      resultado = Availability::ProjectTemplateService.deactivate(project: project, id: alvo.id, actor: actor)

      expect(resultado[:status]).to eq(422)
      expect(resultado[:error]).to include('obrigatório')
      espera_fila_vazia
      expect(alvo.reload).to be_is_active
    end

    it 'padrão com DEPENDENTE obrigatório é recusado, e o dependente é nomeado' do
      # A consulta do legado filtrava `project_id: self.id` — o id do PADRÃO no
      # lugar do id do projeto —, então nunca achava dependente nenhum.
      raiz = padrao(is_mandatory: true)
      filho = padrao(parent_template_id: raiz.id, is_mandatory: true)
      # A raiz é obrigatória, então quem testamos é um irmão não obrigatório com
      # descendente obrigatório.
      pai = padrao
      dependente = padrao(parent_template_id: pai.id, title: 'Dependente obrigatório')
      dependente.update_columns(is_mandatory: true)

      resultado = Availability::ProjectTemplateService.deactivate(project: project, id: pai.id, actor: actor)

      expect(resultado[:status]).to eq(422)
      expect(resultado[:error]).to include('Dependente obrigatório')
      espera_fila_vazia
      expect([raiz, filho]).to all(be_is_active)
    end

    it 'OPS-123 — pai SEM lançamento na data conclui normalmente' do
      raiz = padrao
      filho = padrao(parent_template_id: raiz.id)
      lancar(filho, 100)
      # Apaga o lançamento do pai: é o cenário em que o legado fazia
      # `recalculate_entry.id` sobre `nil` e derrubava o job inteiro.
      AvailabilityEntry.where(availability_template_id: raiz.id).delete_all

      expect { DeactivateProjectTemplateJob.perform_now(filho.id, actor.id) }.not_to raise_error
      expect(filho.reload).not_to be_is_active
      expect(filho.reload).not_to be_locked
    end
  end

  # -------------------------------------------------------------------
  describe 'remoção (BE-146 / DC-20 / OPS-124)' do
    it 'padrão COM LANÇAMENTOS responde 422 e os lançamentos PERMANECEM' do
      alvo = padrao
      lancar(alvo, 100)

      resultado = Availability::ProjectTemplateService.destroy(project: project, id: alvo.id, actor: actor)

      expect(resultado[:status]).to eq(422)
      expect(resultado[:error]).to include('lançamento')
      espera_fila_vazia
      expect(AvailabilityEntry.where(availability_template_id: alvo.id)).to be_present
      expect(ProjectAvailabilityTemplate.exists?(alvo.id)).to be(true)
    end

    it 'padrão de origem GLOBAL não é removível pela rota do projeto' do
      global = create(:global_availability_template)
      Availability::GlobalSeeder.insert_into_project!(project, global)
      derivado = ProjectAvailabilityTemplate.for_project(project)
                                            .find_by(global_availability_template_id: global.id)

      resultado = Availability::ProjectTemplateService.destroy(project: project, id: derivado.id, actor: actor)

      expect(resultado[:status]).to eq(422)
      expect(resultado[:error]).to include('catálogo global')
    end

    it 'remove a subárvore inteira quando não há lançamento' do
      raiz = padrao
      filho = padrao(parent_template_id: raiz.id)

      RemoveProjectTemplateJob.perform_now(raiz.id, actor.id)

      expect(ProjectAvailabilityTemplate.where(id: [raiz.id, filho.id])).to be_empty
    end

    it 'OPS-124 — reexecutar depois de concluída termina SEM erro' do
      alvo = padrao
      RemoveProjectTemplateJob.perform_now(alvo.id, actor.id)

      expect { RemoveProjectTemplateJob.perform_now(alvo.id, actor.id) }.not_to raise_error
    end

    it 'OPS-124 — falha no meio da remoção deixa NADA persistido' do
      raiz = padrao
      filho = padrao(parent_template_id: raiz.id)
      raiz.lock!('Removendo.', actor: actor)

      allow_any_instance_of(RemoveProjectTemplateJob).to receive(:recalcular_afetados)
        .and_raise(StandardError, 'falha depois do destroy')

      expect { RemoveProjectTemplateJob.perform_now(raiz.id, actor.id) }.to raise_error(StandardError)

      # A transação cobre só o `destroy`; o recálculo vem depois e a falha nele
      # não ressuscita nada. O que **não** pode acontecer é sobrar meia
      # subárvore, e o teste confere as duas pontas.
      expect(ProjectAvailabilityTemplate.where(id: [raiz.id, filho.id])).to be_empty
    end
  end

  # -------------------------------------------------------------------
  describe 'semeadura e propagação (OPS-081, OPS-120, OPS-121)' do
    it 'copia `is_adjusted` — o legado NÃO copiava, e todo padrão nascia não ajustado' do
      global = create(:global_availability_template, :corrigido)

      SeedGlobalTemplatesJob.perform_now(project.id)

      derivado = ProjectAvailabilityTemplate.for_project(project)
                                            .find_by(global_availability_template_id: global.id)
      expect(derivado.is_adjusted).to be(true)
    end

    it 'é IDEMPOTENTE — rodar duas vezes não duplica a árvore' do
      create(:global_availability_template)
      create(:global_availability_template)

      SeedGlobalTemplatesJob.perform_now(project.id)
      antes = ProjectAvailabilityTemplate.for_project(project).count
      SeedGlobalTemplatesJob.perform_now(project.id)

      expect(ProjectAvailabilityTemplate.for_project(project).count).to eq(antes)
    end

    it 'preserva a hierarquia do catálogo' do
      raiz = create(:global_availability_template)
      filho = create(:global_availability_template, parent_template_id: raiz.id)

      SeedGlobalTemplatesJob.perform_now(project.id)

      derivado_raiz = ProjectAvailabilityTemplate.find_by(global_availability_template_id: raiz.id)
      derivado_filho = ProjectAvailabilityTemplate.find_by(global_availability_template_id: filho.id)
      expect(derivado_filho.parent_template_id).to eq(derivado_raiz.id)
      expect(derivado_filho.level).to eq(2)
    end

    it 'OPS-121 — a propagação NÃO força obrigatoriedade a 1: copia o valor do global' do
      global = create(:global_availability_template, is_mandatory: false)

      PropagateGlobalTemplateJob.perform_now(global.id, nil, 'insert')

      derivado = ProjectAvailabilityTemplate.for_project(project)
                                            .find_by(global_availability_template_id: global.id)
      expect(derivado.is_mandatory).to be(false)
    end

    it 'OPS-121 — o progresso é publicado no canal DE CADA PROJETO, não num lugar global' do
      outro = create(:project)
      global = create(:global_availability_template)

      # **Exatamente uma vez por projeto** — a mesma asserção que o spec do
      # `WhatsappInstanceChannel` faz, e pelo mesmo motivo: dois eventos por
      # projeto fariam a tela invalidar a consulta em dobro.
      expect { PropagateGlobalTemplateJob.perform_now(global.id, nil, 'insert') }
        .to have_broadcasted_to(ProjectProgressChannel.stream_name_for(project.id)).exactly(:once)
        .and have_broadcasted_to(ProjectProgressChannel.stream_name_for(outro.id)).exactly(:once)
    end

    it 'DC-31 — alterar `is_adjusted` no catálogo PROPAGA aos derivados' do
      global = create(:global_availability_template, is_adjusted: false)
      Availability::GlobalSeeder.insert_into_project!(project, global)
      derivado = ProjectAvailabilityTemplate.find_by(global_availability_template_id: global.id)
      expect(derivado.is_adjusted).to be(false)

      global.update_columns(is_adjusted: true)
      PropagateGlobalTemplateJob.perform_now(global.id, nil, 'sync_attributes')

      expect(derivado.reload.is_adjusted).to be(true)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

# S13 / tarefa 3.3 — **OPS-465: as DUAS tarefas da criação de projeto são
# enfileiradas.**
#
# ## Por que este arquivo existe
#
# O `SeedGlobalTemplatesJob` foi entregue pela S11 — correto, idempotente, com
# progresso item a item e com spec próprio — e **ninguém o chamava**. O
# comentário de `ProjectService#create` reservava a linha (*"Ela se enfileira
# aqui … quando existir"*), o job passou a existir, e a linha nunca foi escrita.
# Projeto novo nascia **sem nenhum padrão de disponibilidade**, e nada acusava:
# não há erro quando ninguém chama.
#
# É uma variante nova da lição do checkpoint ("portão verde prova que o código
# CARREGA, não que ele FUNCIONA"): aqui nem o spec mentia — ele testava o job, e
# o job estava certo. **O que faltava era o chamador, e chamador ausente não
# reprova em portão nenhum.** Este arquivo é o portão que faltava.
#
# No legado as duas saíam juntas do `after_create`
# (`../sfg/app/models/project.rb:74` e `:82`).
RSpec.describe 'Criação de projeto — as duas tarefas de segundo plano (OPS-465)' do
  before do
    UserType.seed_default_types!
    allow(LinkDefaultMembersJob).to receive(:perform_later)
    allow(SeedGlobalTemplatesJob).to receive(:perform_later)
  end

  let(:actor) { create(:user, user_type: UserType.admin) }

  it 'criar projeto enfileira o vínculo de membros padrão E a semeadura do catálogo' do
    resultado = ProjectService.create(actor: actor, attrs: { name: 'Projeto Novo', slug: 'projeto-novo' })

    expect(resultado[:status]).to eq(201)
    projeto = resultado[:data]

    expect(LinkDefaultMembersJob).to have_received(:perform_later).with(projeto.id).once
    expect(SeedGlobalTemplatesJob).to have_received(:perform_later).with(projeto.id, actor.id).once
  end

  it 'limpar o projeto de treinamento REPÕE o catálogo — o WIPE_ORDER apaga os padrões' do
    projeto = Project.create!(name: 'Treino', slug: 'treino', owner: actor, is_sandbox: true)

    ProjectResetService.call(project: projeto, actor: actor)

    expect(SeedGlobalTemplatesJob).to have_received(:perform_later).with(projeto.id, actor.id).once
  end

  it 'os dois jobs têm identificador PRÓPRIO — no legado escreviam no mesmo `job_id`' do
    # `self.job_id = job.id` duas vezes seguidas no `after_create` do legado: a
    # barra do usuário mostrava o progresso de uma tarefa e o fim da outra.
    expect(LinkDefaultMembersJob.job_identifier('abc')).not_to eq(SeedGlobalTemplatesJob.job_identifier('abc'))
  end
end

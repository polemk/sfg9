# frozen_string_literal: true

require 'rails_helper'

# S13 / tarefa 3.6 — **OPS-468: o `rescue` vazio vira erro consultável.**
#
# O legado (`../sfg/lib/insert_projects_on_default_user_job.rb:11-12`) tem
# literalmente isto:
#
#     rescue => e
#     end
#
# Sem log, sem trilha, sem estado. Somado a `destroy_failed_jobs? false`, a
# fila marcava sucesso e o usuário ficava sem projeto **sem deixar rastro**
# (D-79). O equivalente no ai9 é o `DefaultMemberJob` (S0), e o que esta fatia
# exige dele é que a falha nomeie **job, usuário e causa** — nos dois canais em
# que alguém vai procurar: o log e a tela.
#
# O portão de leitura de código (`job_discipline_spec.rb`) já impede o `rescue`
# largo sem `raise`. Este arquivo prova o outro lado: que quando a falha
# realmente acontece, ela **aparece**.
RSpec.describe 'Falha de job é consultável (OPS-468 / D-79)' do
  before { UserType.seed_default_types! }

  let(:dono) { create(:user, user_type: UserType.admin) }
  let!(:projeto) { Project.create!(name: 'A', slug: 'a', owner: dono) }

  describe 'DefaultMemberJob — o job que substitui InsertProjectsOnDefaultUserJob' do
    let(:user) { create(:user, user_type: UserType.colaborador) }

    def descartar!(erro)
      job = DefaultMemberJob.new(user.id)
      DefaultMemberJob.after_discard_procs.each { |bloco| bloco.call(job, erro) }
    end

    it 'o log nomeia JOB, USUÁRIO e CAUSA — o legado não escrevia nada' do
      mensagens = []
      allow(Rails.logger).to receive(:error) { |m| mensagens << m }

      descartar!(ActiveRecord::RecordInvalid.new(User.new))

      expect(mensagens.join("\n")).to include('DefaultMemberJob')
        .and include(user.id)
        .and include('ActiveRecord::RecordInvalid')
    end

    it 'a tela é avisada pelo cabo com status `failed` — a barra não gira para sempre' do
      expect { descartar!(StandardError.new('SMTP fora do ar')) }
        .to have_broadcasted_to(ProjectProgressChannel.stream_name_for(projeto.id))
        .with(hash_including(status: 'failed', error: 'SMTP fora do ar'))
    end

    it 'o `rescue` do laço trata SÓ a corrida de índice único, não tudo' do
      fonte = File.read(Rails.root.join('app/jobs/default_member_job.rb'))
      # `rescue ActiveRecord::RecordNotUnique` é caso conhecido e esperado; um
      # `rescue StandardError` mudo aqui seria o D-79 de volta.
      expect(fonte).to include('rescue ActiveRecord::RecordNotUnique')
      expect(fonte).not_to match(/^\s*rescue\s*(?:$|=>|StandardError\b)/)
    end
  end
end

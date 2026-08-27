# frozen_string_literal: true

require 'rails_helper'

# S0 / BE-044, BE-045, BE-046, BE-099 — participação em projeto.
#
# As três condições que no legado viviam na view viram regra de servidor, e cada
# uma é verificada com o **par permitido/negado** (5.3.1). Um teste que só
# verificasse a negação passaria com a regra negando tudo.
RSpec.describe 'API V1 Memberships', type: :request do
  before do
    UserType.seed_default_types!
    # **DEC-108** — adicionar membro passou a exigir `may_modify_public_entries`,
    # que no legado só escondia a caixa «Adicionar Membro»
    # (`projects/detail/tabs/_tab_geral.html.erb:76`). Sem o catálogo semeado,
    # nenhum papel tem a concessão e todo POST daqui viraria 403 — o gate em si
    # tem spec próprio em `abilities_enforcement_spec.rb`.
    Seeds::Reference::Permissions.call!
  end

  let(:dono) { create(:user, user_type: UserType.admin, name: 'Dono') }
  let(:gerente) { create(:user, user_type: UserType.gerente, name: 'Gerente') }
  let(:colaborador) { create(:user, user_type: UserType.colaborador, name: 'Colaborador') }
  let!(:projeto) { create_project_with_owner(dono, slug: 'proj', name: 'Projeto') }

  describe 'as 3 condições de servidor da remoção (5.3.1)' do
    let!(:membro_dono) { Membership.find_by!(project: projeto, user: dono) }
    let!(:membro_gerente) { Membership.create!(project: projeto, user: gerente, role: 'participante') }
    let!(:membro_colab) { Membership.create!(project: projeto, user: colaborador, role: 'participante') }

    it 'NÃO remove o dono do projeto — e REMOVE um participante comum' do
      delete "/api/v1/memberships/#{membro_dono.id}", headers: auth_headers(gerente, project: projeto)
      expect(response).to have_http_status(403)
      expect(JSON.parse(response.body).dig('details', 'code')).to eq('OWNER_PROTECTED')
      expect(Membership.exists?(membro_dono.id)).to be(true)

      delete "/api/v1/memberships/#{membro_colab.id}", headers: auth_headers(gerente, project: projeto)
      expect(response).to have_http_status(204)
      expect(Membership.exists?(membro_colab.id)).to be(false)
    end

    it 'NÃO remove a si mesmo — e remove outra pessoa' do
      delete "/api/v1/memberships/#{membro_gerente.id}", headers: auth_headers(gerente, project: projeto)
      expect(response).to have_http_status(403)
      expect(JSON.parse(response.body).dig('details', 'code')).to eq('SELF_REMOVAL')
      expect(Membership.exists?(membro_gerente.id)).to be(true)

      delete "/api/v1/memberships/#{membro_colab.id}", headers: auth_headers(gerente, project: projeto)
      expect(response).to have_http_status(204)
    end

    it 'o readonly NÃO remove ninguém — e o mesmo usuário sem readonly remove' do
      Seeds::Reference::Permissions.call!
      UserPermission.create!(user: gerente, permission: Permission.find_by(key: 'user_is_readonly'),
                             source: 'manual', granted_at: Time.current)

      delete "/api/v1/memberships/#{membro_colab.id}", headers: auth_headers(gerente, project: projeto)
      expect(response).to have_http_status(403)
      expect(JSON.parse(response.body)['code']).to eq('READONLY_RESTRICTED')
      expect(Membership.exists?(membro_colab.id)).to be(true)

      UserPermission.where(user: gerente).update_all(revoked_at: Time.current)
      delete "/api/v1/memberships/#{membro_colab.id}", headers: auth_headers(gerente, project: projeto)
      expect(response).to have_http_status(204)
    end
  end

  # 5.3.2 / D-28 + D-34
  describe 'auto-participação' do
    it 'nenhuma sessão se adiciona a um projeto — mas adiciona outra pessoa' do
      outro_projeto = create_project_with_owner(dono, slug: 'outro')
      Membership.create!(project: outro_projeto, user: gerente, role: 'participante')

      post '/api/v1/memberships', params: { user_id: gerente.id },
                                  headers: auth_headers(gerente, project: outro_projeto)
      expect(response).to have_http_status(403)
      expect(JSON.parse(response.body).dig('details', 'code')).to eq('SELF_MEMBERSHIP')

      post '/api/v1/memberships', params: { user_id: colaborador.id },
                                  headers: auth_headers(gerente, project: outro_projeto)
      expect(response).to have_http_status(201)
    end
  end

  # 2.8 / DB-018
  describe 'revogar participação libera o projeto corrente de quem saiu' do
    it 'limpa o current_project_id do removido — e não mexe no de quem ficou' do
      membro_colab = Membership.create!(project: projeto, user: colaborador, role: 'participante')
      colaborador.update!(current_project_id: projeto.id)
      dono.update!(current_project_id: projeto.id)

      delete "/api/v1/memberships/#{membro_colab.id}", headers: auth_headers(dono, project: projeto)
      expect(response).to have_http_status(204)

      expect(colaborador.reload.current_project_id).to be_nil
      expect(dono.reload.current_project_id).to eq(projeto.id)
    end

    it 'recalcula para o único projeto restante em vez de deixar nulo' do
      outro = create_project_with_owner(dono, slug: 'resta')
      membro = Membership.create!(project: projeto, user: colaborador, role: 'participante')
      Membership.create!(project: outro, user: colaborador, role: 'participante')
      colaborador.update!(current_project_id: projeto.id)

      delete "/api/v1/memberships/#{membro.id}", headers: auth_headers(dono, project: projeto)
      expect(colaborador.reload.current_project_id).to eq(outro.id)
    end
  end

  # BE-044
  describe 'GET /api/v1/memberships/candidates' do
    let!(:ja_membro) { Membership.create!(project: projeto, user: colaborador, role: 'participante') }
    let!(:nao_membro) { create(:user, user_type: UserType.colaborador, name: 'Fulano de Tal') }

    it 'NÃO lista quem já é membro — e LISTA quem não é' do
      get '/api/v1/memberships/candidates', headers: auth_headers(dono, project: projeto)

      expect(response).to have_http_status(200)
      ids = JSON.parse(response.body)['candidates'].map { |c| c['id'] }
      expect(ids).not_to include(colaborador.id)
      expect(ids).to include(nao_membro.id)
    end

    it 'busca com termo VAZIO devolve lista válida' do
      get '/api/v1/memberships/candidates', params: { q: '' }, headers: auth_headers(dono, project: projeto)
      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)['candidates']).not_to be_empty
    end

    it 'busca com termo filtra de verdade' do
      get '/api/v1/memberships/candidates', params: { q: 'Fulano' }, headers: auth_headers(dono, project: projeto)
      names = JSON.parse(response.body)['candidates'].map { |c| c['name'] }
      expect(names).to eq(['Fulano de Tal'])
    end

    it 'emite o envelope de paginação em cabeçalho (DEC-62)' do
      get '/api/v1/memberships/candidates', params: { per_page: 1 },
                                            headers: auth_headers(dono, project: projeto)
      expect(response.headers['X-Total-Count']).to be_present
      expect(response.headers['X-Page']).to eq('1')
      expect(response.headers['X-Per-Page']).to eq('1')
      expect(response.headers['X-Total-Pages']).to be_present
    end
  end

  describe 'autorização por papel (DEC-18.5)' do
    it 'Colaborador NÃO cria participação — e Gerente cria' do
      Membership.create!(project: projeto, user: colaborador, role: 'participante')
      Membership.create!(project: projeto, user: gerente, role: 'participante')
      alvo = create(:user, user_type: UserType.colaborador)

      post '/api/v1/memberships', params: { user_id: alvo.id },
                                  headers: auth_headers(colaborador, project: projeto)
      expect(response).to have_http_status(403)

      post '/api/v1/memberships', params: { user_id: alvo.id },
                                  headers: auth_headers(gerente, project: projeto)
      expect(response).to have_http_status(201)
    end

    it 'Colaborador LÊ a lista de membros' do
      Membership.create!(project: projeto, user: colaborador, role: 'participante')
      get '/api/v1/memberships', headers: auth_headers(colaborador, project: projeto)
      expect(response).to have_http_status(200)
    end
  end

  describe 'unicidade da participação' do
    it 'não duplica: o mesmo usuário no mesmo projeto é rejeitado' do
      Membership.create!(project: projeto, user: colaborador, role: 'participante')
      post '/api/v1/memberships', params: { user_id: colaborador.id }, headers: auth_headers(dono, project: projeto)
      expect(response).to have_http_status(422)
    end
  end
end

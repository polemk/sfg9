# frozen_string_literal: true

require 'rails_helper'

# **DEC-108** — as 6 abilities que voltaram, provadas no endpoint.
#
# ## Por que este arquivo existe, e por que cada exemplo tem dois lados
#
# No legado essas seis eram **gate de view**: o `if` escondia o botão e a rota
# continuava aberta (a família do **D-34**). Um teste que só verificasse "a
# checagem existe" passaria com a checagem apontando para o lado errado — é a
# mesma armadilha que a **DEC-41** já tinha nomeado para a hierarquia. Então
# cada exemplo prova **o negado e o permitido**, no mesmo endpoint que a tela
# chama.
#
# A DEC-30 manda replicar regra, cálculo e dado do legado. A exceção que
# sobrevive ao adendo é **segurança e autorização**: replicar um gate que só
# existe no CSS não é paridade, é portar a vulnerabilidade.
RSpec.describe 'DEC-108 — as abilities checadas no servidor', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:admin) { create(:user, user_type: UserType.admin) }
  let(:alvo)  { create(:user, user_type: UserType.colaborador) }

  # Liga/desliga a ability **do papel do Admin**, que é onde o default mora.
  # Escrever direto na tabela (e não pelo endpoint) mantém o exemplo focado no
  # gate que ele está provando — a rota de edição já tem spec próprio.
  def conceder(key, granted: true, limit_value: nil)
    permission = Permission.find_by!(key: key)
    record = UserTypePermission.find_or_initialize_by(user_type: UserType.admin, permission: permission)
    record.granted = granted
    record.limit_value = limit_value
    record.save!
  end

  describe 'may_create_users — POST /api/v1/users' do
    let(:corpo) { { email: "nova-#{SecureRandom.hex(4)}@safegold.test", name: 'Conta nova' } }

    it 'NEGA com 403 sem a permissão — e CRIA com ela' do
      conceder('may_create_users', granted: false)
      post '/api/v1/users', params: corpo, headers: auth_headers(admin)
      expect(response).to have_http_status(403)
      expect(JSON.parse(response.body).dig('details', 'code')).to eq('PERMISSION_REQUIRED')
      expect(JSON.parse(response.body).dig('details', 'permission')).to eq('may_create_users')

      conceder('may_create_users', granted: true)
      expect { post '/api/v1/users', params: corpo, headers: auth_headers(admin) }
        .to change(User, :count).by(1)
      expect(response).to have_http_status(201)
    end
  end

  describe 'max_users_amount — o teto é comparado, não só exibido' do
    # No legado o número só aparecia no título da tela
    # (`registrations/index.html.erb:7`, `"#{@users.size}/#{max}"`) e **nada**
    # comparava. A contagem é a mesma de lá: o total de contas do sistema.
    it 'responde 422 com o teto estourado — e 201 com folga' do
      # `admin` é `let` preguiçoso: forçar a criação ANTES é o que faz
      # `User.count` medir o efeito do endpoint, e não o da própria sessão.
      cabecalhos = auth_headers(admin)
      conceder('may_create_users', granted: true)
      conceder('max_users_amount', limit_value: User.count)

      expect do
        post '/api/v1/users', params: { email: 'estoura@safegold.test', name: 'Estoura' },
                              headers: cabecalhos
      end.not_to change(User, :count)
      expect(response).to have_http_status(422)
      corpo = JSON.parse(response.body)
      expect(corpo.dig('details', 'code')).to eq('LIMIT_EXCEEDED')
      expect(corpo.dig('details', 'permission')).to eq('max_users_amount')

      conceder('max_users_amount', limit_value: 9999)
      post '/api/v1/users', params: { email: 'passa@safegold.test', name: 'Passa' },
                            headers: auth_headers(admin)
      expect(response).to have_http_status(201)
    end

    it 'teto NULO é SEM LIMITE, e teto ZERO é NENHUM — os dois existem no legado' do
      conceder('may_create_users', granted: true)

      conceder('max_users_amount', limit_value: nil)
      post '/api/v1/users', params: { email: 'sem-limite@safegold.test', name: 'Sem limite' },
                            headers: auth_headers(admin)
      expect(response).to have_http_status(201)

      conceder('max_users_amount', limit_value: 0)
      post '/api/v1/users', params: { email: 'zero@safegold.test', name: 'Zero' },
                            headers: auth_headers(admin)
      expect(response).to have_http_status(422)
    end
  end

  describe 'may_invite_users — POST /api/v1/users/:id/invite' do
    it 'NEGA com 403 sem a permissão — e convida com ela' do
      conceder('may_invite_users', granted: false)
      post "/api/v1/users/#{alvo.id}/invite", headers: auth_headers(admin)
      expect(response).to have_http_status(403)
      expect(JSON.parse(response.body).dig('details', 'permission')).to eq('may_invite_users')

      conceder('may_invite_users', granted: true)
      expect { post "/api/v1/users/#{alvo.id}/invite", headers: auth_headers(admin) }
        .to change(LoginCode, :count).by(1)
      expect(response).to have_http_status(200)
      # O convite marca quem convidou — é o que dá o que contar para o teto.
      expect(LoginCode.order(:created_at).last.invited_by_id).to eq(admin.id)
    end
  end

  describe 'max_invitations_amount — teto de convites EM ABERTO' do
    before { conceder('may_invite_users', granted: true) }

    it 'responde 422 com o teto estourado — e 200 com folga' do
      conceder('max_invitations_amount', limit_value: 0)
      post "/api/v1/users/#{alvo.id}/invite", headers: auth_headers(admin)
      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body).dig('details', 'permission')).to eq('max_invitations_amount')

      conceder('max_invitations_amount', limit_value: 5)
      post "/api/v1/users/#{alvo.id}/invite", headers: auth_headers(admin)
      expect(response).to have_http_status(200)
    end

    it 'convite USADO libera a vaga — o teto é de convites em aberto, não de convites emitidos na vida' do
      conceder('max_invitations_amount', limit_value: 1)

      post "/api/v1/users/#{alvo.id}/invite", headers: auth_headers(admin)
      expect(response).to have_http_status(200)

      # O segundo estoura: já há um em aberto.
      post "/api/v1/users/#{alvo.id}/invite", headers: auth_headers(admin)
      expect(response).to have_http_status(422)

      LoginCode.pending_invitations.each(&:use!)

      post "/api/v1/users/#{alvo.id}/invite", headers: auth_headers(admin)
      expect(response).to have_http_status(200)
    end
  end

  describe 'may_delete_users — DELETE /api/v1/users/:id' do
    it 'NEGA com 403 sem a permissão — e remove com ela' do
      cabecalhos = auth_headers(admin)
      alvo_id = alvo.id
      conceder('may_delete_users', granted: false)
      expect { delete "/api/v1/users/#{alvo_id}", headers: cabecalhos }
        .not_to change(User, :count)
      expect(response).to have_http_status(403)
      expect(JSON.parse(response.body).dig('details', 'permission')).to eq('may_delete_users')

      conceder('may_delete_users', granted: true)
      delete "/api/v1/users/#{alvo_id}", headers: cabecalhos
      expect(response).to have_http_status(204)
      expect(User.exists?(alvo_id)).to be(false)
    end

    # BE-014 — encerrar a PRÓPRIA conta é direito do titular, provado por
    # código; não é o poder administrativo de que fala esta ability. Sem esta
    # ressalva o Colaborador — o papel mais numeroso — não sairia do sistema.
    it 'NÃO alcança a auto-remoção: sem a ability, o titular ainda encerra a própria conta' do
      colaborador = create(:user, user_type: UserType.colaborador)
      delete "/api/v1/users/#{colaborador.id}", headers: auth_headers(colaborador)

      # Não passa pelo gate de permissão: para no pedido do código de confirmação.
      expect(response).not_to have_http_status(403)
      expect(JSON.parse(response.body)['message']).to match(/código/i)
    end
  end

  describe 'may_modify_public_entries — POST /api/v1/memberships' do
    let(:projeto)  { create_project_with_owner(admin) }
    let(:candidato) { create(:user, user_type: UserType.colaborador) }

    it 'NEGA com 403 sem a permissão — e vincula com ela' do
      conceder('may_modify_public_entries', granted: false)
      post '/api/v1/memberships', params: { user_id: candidato.id },
                                  headers: auth_headers(admin, project: projeto)
      expect(response).to have_http_status(403)
      expect(JSON.parse(response.body).dig('details', 'permission')).to eq('may_modify_public_entries')

      # O autocomplete é a MESMA caixa da tela do legado, então tem o mesmo gate.
      get '/api/v1/memberships/candidates', params: { q: '' },
                                            headers: auth_headers(admin, project: projeto)
      expect(response).to have_http_status(403)

      conceder('may_modify_public_entries', granted: true)
      expect do
        post '/api/v1/memberships', params: { user_id: candidato.id },
                                    headers: auth_headers(admin, project: projeto)
      end.to change(Membership, :count).by(1)
      expect(response).to have_http_status(201)
    end

    # No legado a remoção estava atrás de `user_is_readonly`, não desta ability
    # (`memberships/list/_widget.html.erb:23`). Portar o gate errado seria
    # inventar uma restrição que nunca existiu.
    it 'NÃO gateia a REMOÇÃO de membro — só a adição' do
      conceder('may_modify_public_entries', granted: true)
      post '/api/v1/memberships', params: { user_id: candidato.id },
                                  headers: auth_headers(admin, project: projeto)
      membership_id = JSON.parse(response.body)['id']

      conceder('may_modify_public_entries', granted: false)
      delete "/api/v1/memberships/#{membership_id}", headers: auth_headers(admin, project: projeto)
      expect(response).to have_http_status(200).or have_http_status(204)
      expect(Membership.exists?(membership_id)).to be(false)
    end
  end

  describe 'o catálogo servido' do
    it 'tem as 7 chaves da DEC-108, com o tipo de cada uma' do
      get '/api/v1/permissions', headers: auth_headers(admin)
      expect(response).to have_http_status(200)

      linhas = JSON.parse(response.body)['permissions']
      expect(linhas.map { |l| l['key'] }).to contain_exactly(
        'user_is_readonly', 'may_create_users', 'may_invite_users', 'may_delete_users',
        'may_modify_public_entries', 'max_users_amount', 'max_invitations_amount'
      )
      limites = linhas.select { |l| l['kind'] == 'limit' }.map { |l| l['key'] }
      expect(limites).to contain_exactly('max_users_amount', 'max_invitations_amount')
    end

    # As 10 sem call site nenhum fora do seed. Um teste que só conte "são 7"
    # passaria com a chave errada entre elas.
    it 'NÃO traz nenhuma das 10 descartadas' do
      descartadas = %w[
        may_create_private_entries may_modify_private_entries may_read_private_entries
        may_delete_private_entries may_create_public_entries may_read_public_entries
        may_delete_public_entries may_read_users max_private_entries_amount
        max_public_entries_amount
      ]
      expect(Permission.where(key: descartadas)).to be_empty
    end
  end
end

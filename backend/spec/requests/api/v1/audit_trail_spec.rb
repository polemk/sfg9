# frozen_string_literal: true

require 'rails_helper'

# OPS-086 / DEC-59 / DEC-77 / DEC-78 — a trilha de auditoria é o `paper_trail`.
RSpec.describe 'Trilha de auditoria', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:og) { create(:user, user_type: UserType.og) }
  let(:admin) { create(:user, user_type: UserType.admin) }
  let(:gerente) { create(:user, user_type: UserType.gerente) }
  let(:colaborador) { create(:user, user_type: UserType.colaborador) }

  describe 'não existe uma segunda trilha (DS0-1 revista pelo DEC-59)' do
    it 'não há AuditEvent, e permission_audit_logs continua sem produtor' do
      expect(defined?(AuditEvent)).to be_nil
      expect(PermissionAuditLog.count).to eq(0)
    end
  end

  describe 'concessão de permissão grava na trilha (3.10)' do
    it 'registra quem, sobre quem, o quê, quando e por quê' do
      expect do
        put "/api/v1/users/#{colaborador.id}/permissions/user_is_readonly",
            params: { granted: true, reason: 'pedido do cliente' }, headers: auth_headers(og)
      end.to change { PaperTrail::Version.where(item_type: 'UserPermission').count }.by(1)

      version = PaperTrail::Version.where(item_type: 'UserPermission').last
      expect(version.event).to eq('create')          # o quê
      expect(version.whodunnit).to eq(og.id.to_s)    # quem
      expect(version.reason).to eq('pedido do cliente') # por quê
      expect(version.created_at).to be_present       # quando
      expect(UserPermission.find(version.item_id).user_id).to eq(colaborador.id) # sobre quem
    end

    it 'a revogação também grava' do
      put "/api/v1/users/#{colaborador.id}/permissions/user_is_readonly",
          params: { granted: true }, headers: auth_headers(og)

      expect do
        put "/api/v1/users/#{colaborador.id}/permissions/user_is_readonly",
            params: { granted: false, reason: 'fim da auditoria' }, headers: auth_headers(og)
      end.to change { PaperTrail::Version.where(item_type: 'UserPermission', event: 'update').count }.by(1)
    end

    # DEC-78 — payload COMPLETO.
    it 'guarda a foto INTEIRA do registro anterior, não só o delta' do
      put "/api/v1/user_types/#{UserType.colaborador.id}/permissions/user_is_readonly",
          params: { granted: true }, headers: auth_headers(og)
      put "/api/v1/user_types/#{UserType.colaborador.id}/permissions/user_is_readonly",
          params: { granted: false }, headers: auth_headers(og)

      version = PaperTrail::Version.where(item_type: 'UserTypePermission', event: 'update').last
      expect(version.object_changes).to be_a(Hash)
      expect(version.object_changes['granted']).to eq([true, false])

      # `object` é a FOTO COMPLETA do estado anterior (DEC-78), não só o campo
      # que mudou — é o que permite reconstruir o registro em qualquer ponto.
      expect(version.object).to be_a(Hash)
      expect(version.object.keys).to include('id', 'user_type_id', 'permission_id', 'granted', 'created_at')
    end
  end

  # DEC-59 #3 — o ponto de ter trilha.
  describe 'whodunnit na impersonação' do
    it 'registra o usuário REAL (true_user), não o impersonado' do
      tokens = Auth::ImpersonateService.start(og, admin.id, reason: 'conferência da trilha')[:data]

      put "/api/v1/users/#{colaborador.id}/permissions/user_is_readonly",
          params: { granted: true },
          headers: { 'Authorization' => "Bearer #{tokens[:access_token]}" }
      expect(response).to have_http_status(200)

      version = PaperTrail::Version.where(item_type: 'UserPermission').last
      expect(version.whodunnit).to eq(og.id.to_s)
      expect(version.whodunnit).not_to eq(admin.id.to_s)
      expect(version.impersonated_id).to eq(admin.id.to_s)
    end
  end

  # 3.11 / DEC-77
  describe 'GET /api/v1/audit_trail' do
    before do
      put "/api/v1/users/#{colaborador.id}/permissions/user_is_readonly",
          params: { granted: true }, headers: auth_headers(og)
    end

    it 'Gerente e Colaborador NÃO leem a trilha global — OG e Admin leem' do
      get '/api/v1/audit_trail', headers: auth_headers(gerente)
      expect(response).to have_http_status(403)

      get '/api/v1/audit_trail', headers: auth_headers(colaborador)
      expect(response).to have_http_status(403)

      get '/api/v1/audit_trail', headers: auth_headers(admin)
      expect(response).to have_http_status(200)

      get '/api/v1/audit_trail', headers: auth_headers(og)
      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)).not_to be_empty
    end

    it 'sem sessão responde 401' do
      get '/api/v1/audit_trail'
      expect(response).to have_http_status(401)
    end

    it 'emite o envelope de paginação em cabeçalho' do
      get '/api/v1/audit_trail', params: { per_page: 1 }, headers: auth_headers(og)
      expect(response.headers['X-Total-Count']).to be_present
      expect(response.headers['X-Total-Pages']).to be_present
    end

    it 'filtra por tipo de registro' do
      get '/api/v1/audit_trail', params: { item_type: 'UserPermission' }, headers: auth_headers(og)
      types = JSON.parse(response.body).map { |v| v['item_type'] }.uniq
      expect(types).to eq(['UserPermission'])
    end

    # S19 / BE-432 — os filtros são COMBINÁVEIS, e o total do envelope é o do
    # filtrado. No legado o `where!` mutava a relação e o `@trackings.size > 0`
    # carregava tudo antes do `limit`.
    it 'dois filtros juntos reduzem o resultado, e o X-Total-Count acompanha' do
      put "/api/v1/user_types/#{UserType.colaborador.id}/permissions/user_is_readonly",
          params: { granted: true }, headers: auth_headers(og)

      get '/api/v1/audit_trail', headers: auth_headers(og)
      total_sem_filtro = response.headers['X-Total-Count'].to_i

      get '/api/v1/audit_trail',
          params: { item_type: 'UserPermission', event: 'create' }, headers: auth_headers(og)
      total_filtrado = response.headers['X-Total-Count'].to_i

      expect(total_filtrado).to be < total_sem_filtro
      expect(JSON.parse(response.body).size).to eq(total_filtrado)
    end

    # FE-440 — o contrato vale nos DOIS sentidos. O `type: DateTime` do Grape
    # aceitaria `03/04/2026` e responderia 200 com a janela errada.
    it 'RECUSA data em formato brasileiro no filtro, com 400' do
      get '/api/v1/audit_trail', params: { from: '31/12/2025' }, headers: auth_headers(og)
      expect(response).to have_http_status(400)

      get '/api/v1/audit_trail', params: { to: '03/04/2026' }, headers: auth_headers(og)
      expect(response).to have_http_status(400)
    end

    it 'filtra por período em ISO-8601 (FE-440)' do
      get '/api/v1/audit_trail',
          params: { from: 1.hour.ago.utc.iso8601, to: 1.hour.from_now.utc.iso8601 },
          headers: auth_headers(og)
      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)).not_to be_empty

      get '/api/v1/audit_trail', params: { to: 2.days.ago.utc.iso8601 }, headers: auth_headers(og)
      expect(JSON.parse(response.body)).to be_empty
    end

    # FE-446 — o payload da trilha.
    describe 'o payload (FE-446)' do
      subject(:versao) do
        get '/api/v1/audit_trail', params: { item_type: 'UserPermission' }, headers: auth_headers(og)
        JSON.parse(response.body).first
      end

      it 'diz quem, sobre o quê, quando e por quê — com o autor resolvido' do
        expect(versao['author']).to include('id' => og.id.to_s, 'name' => og.name)
        expect(versao['item_type']).to eq('UserPermission')
        expect(versao['event']).to eq('create')
        expect(versao['occurred_at']).to match(/\A\d{4}-\d{2}-\d{2}T/)
      end

      # A frase que a timeline mostra é DERIVADA — não há coluna para estourar,
      # então o defeito do legado (resumo > 300 = evento sumia) não tem onde
      # acontecer.
      it 'traz o resumo em pt-BR, com a concordância de gênero do catálogo' do
        expect(versao['summary']).to eq('A permissão do usuário foi criada')
        expect(versao['entity_label']).to eq('permissão do usuário')
      end

      it 'a foto COMPLETA (DEC-78) fica fora da listagem' do
        expect(versao).not_to have_key('snapshot')
        expect(versao).to have_key('changes')
      end

      it 'as datas saem em ISO-8601 UTC, nunca em formato brasileiro' do
        expect(versao['occurred_at']).not_to match(%r{\d{2}/\d{2}/\d{4}})
      end
    end

    describe 'GET /api/v1/audit_trail/:id — o detalhe' do
      it 'traz a foto completa do estado anterior' do
        put "/api/v1/user_types/#{UserType.colaborador.id}/permissions/user_is_readonly",
            params: { granted: true }, headers: auth_headers(og)
        put "/api/v1/user_types/#{UserType.colaborador.id}/permissions/user_is_readonly",
            params: { granted: false }, headers: auth_headers(og)
        alvo = PaperTrail::Version.where(item_type: 'UserTypePermission', event: 'update').last

        get "/api/v1/audit_trail/#{alvo.id}", headers: auth_headers(og)
        expect(response).to have_http_status(200)

        corpo = JSON.parse(response.body)
        expect(corpo['snapshot'].keys).to include('id', 'user_type_id', 'permission_id', 'granted')
        expect(corpo['changes']['granted']).to eq([true, false])
      end

      it 'responde 404 para versão inexistente' do
        get '/api/v1/audit_trail/999999', headers: auth_headers(og)
        expect(response).to have_http_status(404)
      end

      it 'o detalhe tem a MESMA autorização da listagem (DEC-77)' do
        alvo = PaperTrail::Version.last
        get "/api/v1/audit_trail/#{alvo.id}", headers: auth_headers(colaborador)
        expect(response).to have_http_status(403)
      end
    end

    describe 'GET /api/v1/audit_trail/types' do
      it 'entrega o vocabulário do filtro, para a tela não conhecer os models' do
        get '/api/v1/audit_trail/types', headers: auth_headers(og)
        expect(response).to have_http_status(200)
        valores = JSON.parse(response.body)
        expect(valores.map { |t| t['value'] }).to include('UserPermission', 'Project')
        expect(valores.find { |t| t['value'] == 'Project' }['label']).to eq('projeto')
      end
    end
  end

  # DEC-59 #3 / DEC-78 #3
  describe 'o que NÃO entra na trilha' do
    it 'o jti do usuário não é copiado para o payload' do
      user = create(:user, user_type: UserType.colaborador)
      user.update!(jti: SecureRandom.uuid, name: 'Novo nome')

      version = PaperTrail::Version.where(item_type: 'User', item_id: user.id.to_s).last
      expect(version.object_changes.keys).not_to include('jti')
      expect(version.object&.keys || []).not_to include('jti')
    end

    it 'login não gera versão (last_login_at/login_count são ignorados)' do
      user = create(:user, user_type: UserType.colaborador)
      expect { user.update_login_stats! }
        .not_to change { PaperTrail::Version.where(item_type: 'User', item_id: user.id.to_s).count }
    end
  end

  describe PurgeAuditVersionsJob do
    it 'apaga versões além da retenção — e preserva as de dentro' do
      antiga = PaperTrail::Version.create!(item_type: 'User', item_id: 'x', event: 'update',
                                           created_at: 10.years.ago)
      recente = PaperTrail::Version.create!(item_type: 'User', item_id: 'y', event: 'update',
                                            created_at: 1.day.ago)

      described_class.perform_now

      expect(PaperTrail::Version.exists?(antiga.id)).to be(false)
      expect(PaperTrail::Version.exists?(recente.id)).to be(true)
    end
  end
end

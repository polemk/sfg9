# frozen_string_literal: true

require 'rails_helper'

# S4 / 5.3.5–5.3.8 e 7.1.7 — **conexões projeto ↔ indicador**.
#
# Estas quatro tarefas estavam marcadas no razão como "BLOQUEADO por S10 — a
# tabela `indicators` não existe". **O bloqueio era fóssil**: a tabela nasceu em
# `20260826210000`, a S10 fechou 80/80, e o endpoint que a S4 pedia como
# `project_indicator_connections` foi entregue por ela com o nome
# `indicator_connections` — mesmo controller legado
# (`Pub::ProjectIndicatorConnectionsController`), mesmos defeitos corrigidos.
#
# O que este arquivo prova é o **contrato da S4**, e não a implementação:
#
# - **BE-106** — não há `constantize` de parâmetro: o tipo é `Indicator`,
#   escrito no código. O que se testa é o efeito — nenhum parâmetro do cliente
#   escolhe classe.
# - **BE-107 / 7.1.7** — candidatos são os **globais + os deste projeto**, e
#   nenhum específico de outro projeto vaza.
# - **BE-108** — o lote tem os quatro defeitos do BE-103 corrigidos: sem
#   `constantize`, com `save` verificado, com resultado **por item** (não só o
#   último) e com lote vazio recusado em vez de derrubar a ação.
# - **BE-109** — excluir indicador **global** pela rota do projeto é **422**, não
#   500; e o de outro projeto é **404**, não 403 (403 confirmaria que existe).
RSpec.describe 'API V1 Indicator connections', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:gerente) { create(:user, user_type: UserType.gerente) }
  let(:outro) { create(:user, user_type: UserType.gerente) }

  let!(:projeto_a) { create_project_with_owner(gerente, slug: 'ind-a', name: 'Indicadores A') }
  let!(:projeto_b) { create_project_with_owner(outro, slug: 'ind-b', name: 'Indicadores B') }

  let!(:global) { create(:indicator, title: 'INADIMPLENCIA') }
  let!(:do_a) { create(:indicator, :specific, project: projeto_a, title: 'MARGEM A') }
  let!(:do_b) { create(:indicator, :specific, project: projeto_b, title: 'MARGEM B') }

  def corpo = JSON.parse(response.body)

  # O GET devolve **array puro** e a paginação vai nos cabeçalhos — é o contrato
  # que `indicatorConnectionsApi.list` consome (`readPageMeta` lê os headers).

  describe 'GET /indicator_connections — os candidatos (BE-107, 7.1.7)' do
    it 'traz os globais e os DESTE projeto, e nenhum específico de outro' do
      get '/api/v1/indicator_connections', headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      ids = corpo.map { |i| i['id'] }
      expect(ids).to include(global.id, do_a.id)
      # É o coração da 7.1.7: o específico do projeto B não pode aparecer.
      expect(ids).not_to include(do_b.id)
    end

    it 'marca `scope` pela COLUNA e o estado `connected` do projeto corrente' do
      create(:project_indicator_connection, project: projeto_a, indicator: global)

      get '/api/v1/indicator_connections', headers: auth_headers(gerente, project: projeto_a)

      por_id = corpo.index_by { |i| i['id'] }
      expect(por_id[global.id]['scope']).to eq('global')
      expect(por_id[global.id]['connected']).to be(true)
      expect(por_id[do_a.id]['scope']).to eq('project')
      expect(por_id[do_a.id]['connected']).to be(false)
    end

    it 'a conexão do projeto B não marca o global como conectado no projeto A' do
      create(:project_indicator_connection, project: projeto_b, indicator: global)

      get '/api/v1/indicator_connections', headers: auth_headers(gerente, project: projeto_a)

      por_id = corpo.index_by { |i| i['id'] }
      expect(por_id[global.id]['connected']).to be(false)
    end

    it 'a busca FILTRA — no legado `q` era ignorado e o front pedia 200 itens' do
      get '/api/v1/indicator_connections', params: { q: 'MARGEM' },
                                           headers: auth_headers(gerente, project: projeto_a)

      ids = corpo.map { |i| i['id'] }
      expect(ids).to eq([do_a.id])
    end
  end

  describe 'POST /connect e /disconnect — o lote (BE-108)' do
    it 'conecta em lote com resultado POR ITEM' do
      post '/api/v1/indicator_connections/connect',
           params: { indicator_ids: [global.id, do_a.id] },
           headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(corpo['items'].size).to eq(2)
      expect(corpo['items'].map { |i| i['ok'] }).to all(be(true))
      expect(corpo['connected_ids']).to match_array([global.id, do_a.id])
    end

    it 'lote VAZIO é 422 explicado, não uma ação que passa batido' do
      post '/api/v1/indicator_connections/connect', params: { indicator_ids: [] },
                                                    headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(422)
    end

    it 'um id de OUTRO projeto derruba o lote inteiro e nomeia o item — nada é gravado' do
      post '/api/v1/indicator_connections/connect',
           params: { indicator_ids: [global.id, do_b.id] },
           headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(422)
      # É aqui que o legado reportava sucesso: o laço reatribuía `@connection` e
      # só o ÚLTIMO item era inspecionado depois.
      itens = corpo['details']['items']
      expect(itens.find { |i| i['indicator_id'] == do_b.id }['ok']).to be(false)
      # Transacional: o item bom também não ficou.
      expect(ProjectIndicatorConnection.where(project_id: projeto_a.id)).to be_empty
    end

    it 'desconectar o que NÃO está conectado é no-op idempotente, não 500' do
      post '/api/v1/indicator_connections/disconnect', params: { indicator_ids: [global.id] },
                                                       headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(corpo['items'].first['state']).to eq('disconnected')
    end

    it 'desconectar NÃO apaga os lançamentos históricos (Q-R31)' do
      create(:project_indicator_connection, project: projeto_a, indicator: global)
      create(:indicator_entry, project: projeto_a, indicator: global, year: 2025, month: 3, value: 10)

      post '/api/v1/indicator_connections/disconnect', params: { indicator_ids: [global.id] },
                                                       headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(IndicatorEntry.where(project_id: projeto_a.id, indicator_id: global.id).count).to eq(1)
    end
  end

  describe 'DELETE /:indicator_id — excluir o específico (BE-109)' do
    it 'exclui o específico deste projeto por exclusão LÓGICA' do
      delete "/api/v1/indicator_connections/#{do_a.id}", headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(do_a.reload.discarded_at).to be_present
    end

    it 'indicador GLOBAL responde 422, não 500 — e continua vivo' do
      delete "/api/v1/indicator_connections/#{global.id}", headers: auth_headers(gerente, project: projeto_a)

      # No legado este mesmo ramo levantava `NoMethodError`: `@connection` vinha
      # do `before_action` e era uma `Relation`, não um record.
      expect(response).to have_http_status(422)
      expect(global.reload.discarded_at).to be_nil
    end

    it 'indicador de OUTRO projeto é 404, nunca 403 — e continua vivo (7.1.7)' do
      delete "/api/v1/indicator_connections/#{do_b.id}", headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(404)
      expect(do_b.reload.discarded_at).to be_nil
    end

    it 'id malformado é 404, não 500' do
      delete '/api/v1/indicator_connections/nao-e-uuid', headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(404)
    end
  end
end

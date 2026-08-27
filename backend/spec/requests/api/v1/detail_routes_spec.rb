# frozen_string_literal: true

require 'rails_helper'

# **S2 / tarefa 2.8 — as 13 áreas de detalhe, rota por rota.**
#
# No legado a navegação inteira passava por UM despacho
# (`console#show`, com `resource`/`topic`/`section`), e o que ele fazia com um
# `resource` que não tinha template era estourar `MissingTemplate` — 500 na cara
# do usuário por clicar numa linha. É a família **BE-395..BE-409**.
#
# No ai9 não existe mais despacho: cada área tem a sua rota de detalhe. Este
# spec é a conferência que a 2.8 pede, e ele cobre os **dois** lados de cada
# área (disciplina C3 do DEC-41):
#
# - id que existe → **200**;
# - id que não existe → **404 de verdade**, nunca 500 e nunca 200 com casca
#   vazia.
#
# Ele é deliberadamente **raso**: não confere o conteúdo do corpo, que é
# trabalho do spec de cada fatia. O que ele impede é a regressão que a 2.8
# nomeia — uma área perder a rota de detalhe e ninguém notar, porque a lista
# continua abrindo.
#
# ### O que está aqui e o que está no spec da fatia
#
# As 13 áreas foram medidas **rodando**, contra o servidor de dev e com sessão
# de Admin de verdade (`GET` com id real e com uuid fantasma). O resultado está
# no `tasks.md` da S2. Todas as 13 respondem **200 / 404**.
#
# Fixam-se AQUI as áreas cujo detalhe (a) não tinha spec de rota próprio, ou
# (b) foi onde a conferência achou defeito: usuários, projetos, conexões de
# portador (via portador) e empresas, mais a regressão do **405 que era 500**.
# As outras nove — contratos, ajuda, recebíveis, renegociações,
# disponibilidades, operações de risco, garantias, operações estruturadas e
# cobranças/recibos — já têm o `GET :id` coberto no spec da própria fatia, e
# duplicar o `let!` das nove aqui só criaria um segundo lugar para envelhecer.
#
# **Se a sua área nova não estiver coberta em lugar nenhum, acrescente a linha
# aqui**, no mesmo commit da rota.
RSpec.describe 'Rotas de detalhe das 13 áreas (S2 / 2.8)', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  # OG enxerga todos os projetos (DEC-99), o que tira do caminho o ruído de
  # participação — que tem spec próprio em `project_scope_spec.rb`. O ponto aqui
  # é a ROTA existir e discriminar existente de inexistente.
  let(:og) { create(:user, :og) }
  let(:projeto) { create(:project) }

  # Um uuid bem formado que não é de ninguém. Malformado seria um teste mais
  # fraco: o caminho de "não é uuid" já é coberto pelo `UUID_FORMAT` do
  # `CatalogService`, e o que interessa aqui é o id plausível.
  let(:inexistente) { '00000000-0000-4000-8000-000000000000' }

  def headers = auth_headers(og, project: projeto)

  # Cada exemplo recebe o id real e monta as duas requisições.
  def espera_detalhe(rota_com_id, rota_com_fantasma)
    get rota_com_id, headers: headers
    expect(response).to have_http_status(:ok),
                        "#{rota_com_id} respondeu #{response.status} para um id que EXISTE"

    get rota_com_fantasma, headers: headers
    expect(response).to have_http_status(:not_found),
                        "#{rota_com_fantasma} respondeu #{response.status} para um id inexistente — " \
                        'a 2.8 exige 404 de verdade, nunca 500 nem 200'
  end

  it '1. usuários' do
    alvo = create(:user)
    espera_detalhe("/api/v1/users/#{alvo.id}", "/api/v1/users/#{inexistente}")
  end

  it '4. projetos' do
    espera_detalhe("/api/v1/projects/#{projeto.id}", "/api/v1/projects/#{inexistente}")
  end

  # BE-401 — no legado era `carriers` + `section: 'carrier_connections'`. No ai9
  # a conexão é lida pela LISTA (`GET /project_carrier_connections`) e o detalhe
  # equivalente é o do portador.
  it '5. conexões de portador — o detalhe equivalente é o do portador' do
    carrier = create(:carrier)
    ProjectToCarrierConnection.create!(project: projeto, carrier: carrier)

    get '/api/v1/project_carrier_connections', headers: headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).map { |c| c['carrier_id'] }).to include(carrier.id)

    espera_detalhe("/api/v1/carriers/#{carrier.id}", "/api/v1/carriers/#{inexistente}")
  end

  it '9. empresas' do
    empresa = create(:company, project: projeto)
    espera_detalhe("/api/v1/companies/#{empresa.id}", "/api/v1/companies/#{inexistente}")
  end

  # ---------------------------------------------------------------------------
  # **O 500 que a 2.8 existe para eliminar, e que estava vivo.**
  #
  # `project_carrier_connections` expõe `DELETE :id` e não expõe `GET :id`. O
  # `GET` deveria ser 405 — o Grape até monta o cabeçalho `Allow: OPTIONS,
  # DELETE` corretamente —, mas o `rescue_from :all` herdado da base ai9 engolia
  # o `Grape::Exceptions::MethodNotAllowed` e devolvia **500**, com o backtrace
  # inteiro no corpo. Medido no servidor de dev antes da correção.
  #
  # Os dois lados: o verbo certo continua funcionando.
  it 'verbo não suportado numa rota de detalhe é 405, NUNCA 500' do
    carrier = create(:carrier)
    conexao = ProjectToCarrierConnection.create!(project: projeto, carrier: carrier)

    get "/api/v1/project_carrier_connections/#{conexao.id}", headers: headers

    expect(response).to have_http_status(:method_not_allowed)
    expect(response.headers['Allow']).to include('DELETE')
    expect(response.body).not_to include('BACKTRACE'),
                                'o corpo do erro vazava o backtrace inteiro — é informação de infraestrutura'

    delete "/api/v1/project_carrier_connections/#{conexao.id}", headers: headers
    expect(response).to have_http_status(:ok)
  end

  # Uma área que não existe responde 404, e não a casca de outra tela — era o
  # `MissingTemplate` do legado.
  it 'área desconhecida é 404, nunca casca de outra tela' do
    get "/api/v1/nao_existe/#{inexistente}", headers: headers
    expect(response).to have_http_status(:not_found)
  end
end

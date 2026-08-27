# frozen_string_literal: true

require 'rails_helper'

# **BE-112 / BE-142 — criar o padrão de disponibilidade do projeto.**
#
# A conferência de paridade da Phase 4 (27/08/2026) travou os dois: só existia o
# caso NEGATIVO (pai de outro projeto é recusado). O POST bem-sucedido — o
# caminho que o usuário percorre — não tinha exemplo, e junto com ele passou
# despercebida uma divergência.
#
# ## A divergência: `is_mandatory` era gravável, e não devia
#
# O `permit` do legado para o padrão de PROJETO
# (`project_availabilities_controller.rb:143-155`) **não tem o campo**; só o do
# catálogo global tem. Aqui ele estava declarado no `create` e **não no
# `update`** — a assimetria é o que denuncia o descuido.
#
# A obrigatoriedade é atributo da ORIGEM: um padrão de projeto é obrigatório
# porque veio de um global obrigatório, não porque alguém marcou uma caixa. E a
# tela nunca ofereceu o controle — só lê o campo. Pela **DEC-30** (onde a
# pergunta é replicar ou corrigir, a resposta assinada é replicar), o campo saiu
# dos parâmetros.
RSpec.describe 'Api::V1 — criar padrão de disponibilidade do projeto', type: :request do
  before { UserType.seed_default_types! }

  let(:og) { create(:user, :og) }
  let!(:projeto) { create_project_with_owner(og, slug: 'disp-new', name: 'Novo') }
  let(:headers) { auth_headers(og, project: projeto) }

  def json = JSON.parse(response.body)

  def criar(**attrs)
    post '/api/v1/project_availabilities',
         params: { title: 'Caixa', operation_type: 'C', deadline_type: 'CP' }.merge(attrs),
         headers: headers
  end

  it 'cria no PROJETO CORRENTE, com os campos do formulário' do
    criar(title: 'Caixa livre', operation_type: 'D', deadline_type: 'LP')

    expect(response).to have_http_status(:created)
    expect(json['title']).to eq('Caixa livre')
    expect(json['operation_type']).to eq('D')
    expect(json['deadline_type']).to eq('LP')

    registro = ProjectAvailabilityTemplate.find(json['id'])
    expect(registro.project_id).to eq(projeto.id)
    expect(registro.level).to eq(1)
  end

  it 'o nível sai do PAI, não do corpo da requisição' do
    pai = create(:project_availability_template, project: projeto, title: 'Pai')

    criar(title: 'Filho', parent_template_id: pai.id)

    expect(response).to have_http_status(:created)
    expect(ProjectAvailabilityTemplate.find(json['id']).level).to eq(2)
  end

  it 'o AUTOR é quem está autenticado, e não um id vindo do corpo' do
    criar(title: 'Com autor')

    expect(response).to have_http_status(:created)
    expect(ProjectAvailabilityTemplate.find(json['id']).user_id).to eq(og.id)
  end

  # A regra de negócio que o legado tinha e que continua valendo.
  it 'título repetido no MESMO nível é recusado' do
    create(:project_availability_template, project: projeto, title: 'Duplicado')

    criar(title: 'Duplicado')

    expect(response).to have_http_status(:unprocessable_content)
  end

  # ---------------------------------------------------------------- BE-112/142
  describe '`is_mandatory` não é gravável (DEC-30)' do
    it 'mandar `is_mandatory: true` NÃO torna o padrão obrigatório' do
      criar(title: 'Tentativa', is_mandatory: true)

      expect(response).to have_http_status(:created)
      expect(ProjectAvailabilityTemplate.find(json['id']).is_mandatory).to be(false)
    end

    # O parâmetro é ignorado, não recusado: o formulário atual manda
    # `is_mandatory: false` fixo no corpo, e responder 400 quebraria a tela sem
    # que ninguém tivesse pedido nada de errado.
    it 'mandar `is_mandatory: false` também passa, sem erro' do
      criar(title: 'Explícito', is_mandatory: false)

      expect(response).to have_http_status(:created)
      expect(ProjectAvailabilityTemplate.find(json['id']).is_mandatory).to be(false)
    end
  end

  # O caso negativo que já existia, mantido aqui junto do positivo para quem ler
  # o arquivo ver a regra dos dois lados.
  it 'pai de OUTRO projeto é recusado' do
    outro = create(:project)
    alheio = create(:project_availability_template, project: outro, title: 'Alheio')

    criar(title: 'Com pai alheio', parent_template_id: alheio.id)

    expect(response.status).to be_in([404, 422])
    expect(ProjectAvailabilityTemplate.where(title: 'Com pai alheio')).to be_empty
  end
end

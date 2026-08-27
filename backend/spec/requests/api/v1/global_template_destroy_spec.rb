# frozen_string_literal: true

require 'rails_helper'

# **BE-136 — a exclusão do padrão global, em cascata.**
#
# A conferência de paridade da Phase 4 (27/08/2026) travou este item por um
# motivo desconfortável: é o endpoint **mais destrutivo** da fatia — apaga a
# subárvore inteira e desvincula todos os padrões de projeto que apontavam para
# ela — e não tinha **um único exemplo**. O serviço faz quatro coisas numa
# transação, e nenhuma estava provada.
#
# O que o legado fazia, e por que a migração mudou (D-24): lá o `update_all` do
# desvínculo rodava **fora de qualquer transação**, e existia uma rotina manual
# de conserto (`fix_after_global_remove`) justamente porque ele podia falhar no
# meio e deixar padrão de projeto apontando para um global que já não existia.
# Aqui é transacional — e uma rotina de conserto que ninguém precisa chamar só
# vale se a transação for de verdade.
#
# Os quatro efeitos, um exemplo cada:
#   1. a subárvore inteira sai, e não só o nó pedido;
#   2. o padrão de PROJETO que apontava para ela é desvinculado, não apagado —
#      é dado do cliente, e o global é só a origem;
#   3. a posição dos irmãos é recompactada;
#   4. tudo ou nada: falhando um passo, nada sai.
RSpec.describe 'Api::V1 — exclusão do padrão global (BE-136)', type: :request do
  before { UserType.seed_default_types! }

  let(:og) { create(:user, :og) }
  let!(:projeto) { create_project_with_owner(og, slug: 'disp-del', name: 'Exclusão') }
  let(:headers) { auth_headers(og, project: projeto) }

  # Uma árvore de três níveis: raiz > filho > neto. Três níveis, e não dois,
  # porque a exclusão vai do MAIS FUNDO para a raiz — com dois níveis um
  # `destroy_all` chapado passaria e o defeito só apareceria no terceiro.
  let!(:raiz) { create(:global_availability_template, title: 'Raiz') }
  let!(:filho) { create(:global_availability_template, title: 'Filho', parent_template: raiz) }
  let!(:neto) { create(:global_availability_template, title: 'Neto', parent_template: filho) }

  # Uma segunda árvore, intocada: exclusão que leva vizinho junto é o defeito
  # que nenhuma contagem de "removidos" revela.
  let!(:vizinha) { create(:global_availability_template, title: 'Vizinha') }

  def json = JSON.parse(response.body)

  it 'apaga a SUBÁRVORE inteira, e não só o nó pedido' do
    delete "/api/v1/availability_templates/#{raiz.id}", headers: headers

    expect(response).to have_http_status(:ok)
    expect(json['deleted']).to be(true)
    expect(json['removed_count']).to eq(3)

    expect(GlobalAvailabilityTemplate.where(id: [raiz.id, filho.id, neto.id])).to be_empty
    expect(GlobalAvailabilityTemplate.find_by(id: vizinha.id)).to be_present
  end

  it 'apagando o MEIO da árvore, a raiz fica e só o ramo de baixo sai' do
    delete "/api/v1/availability_templates/#{filho.id}", headers: headers

    expect(response).to have_http_status(:ok)
    expect(json['removed_count']).to eq(2)
    expect(GlobalAvailabilityTemplate.find_by(id: raiz.id)).to be_present
    expect(GlobalAvailabilityTemplate.where(id: [filho.id, neto.id])).to be_empty
  end

  it 'DESVINCULA o padrão do projeto — ele é dado do cliente, não some junto' do
    do_projeto = create(:project_availability_template, project: projeto, title: 'Copiado',
                                                        global_availability_template_id: filho.id,
                                                        is_global: true)

    delete "/api/v1/availability_templates/#{raiz.id}", headers: headers

    expect(response).to have_http_status(:ok)
    do_projeto.reload
    # Continua existindo, com o título e o projeto intactos...
    expect(do_projeto.title).to eq('Copiado')
    expect(do_projeto.project_id).to eq(projeto.id)
    # ...e sem a origem, que é o que deixou de existir.
    expect(do_projeto.global_availability_template_id).to be_nil
    expect(do_projeto.is_global).to be(false)
  end

  it 'recompacta a POSIÇÃO dos que sobraram — sem buraco na ordem' do
    primeira = create(:global_availability_template, title: 'Primeira')
    ultima = create(:global_availability_template, title: 'Última')

    delete "/api/v1/availability_templates/#{primeira.id}", headers: headers
    expect(response).to have_http_status(:ok)

    posicoes = GlobalAvailabilityTemplate.where(parent_template_id: nil).order(:position).pluck(:position)
    expect(posicoes).to eq((1..posicoes.size).to_a), "posições com buraco: #{posicoes.inspect}"
    expect(GlobalAvailabilityTemplate.find_by(id: ultima.id)).to be_present
  end

  # A razão de ser da transação (D-24). Se o desvínculo falhar, o padrão global
  # NÃO pode sair: era exatamente esse estado meio-feito que obrigava o legado a
  # ter uma rotina de conserto manual.
  it 'é TUDO OU NADA: falhando o desvínculo, nada é apagado' do
    do_projeto = create(:project_availability_template, project: projeto,
                                                        global_availability_template_id: filho.id,
                                                        is_global: true)

    allow(ProjectAvailabilityTemplate).to receive(:where).and_raise(ActiveRecord::StatementInvalid, 'falha simulada')

    # Direto no SERVIÇO, e não pelo endpoint: a transação é contrato dele, e o
    # Grape captura a exceção antes de ela chegar ao exemplo — pelo HTTP se veria
    # um 500 e não se saberia se o banco ficou meio-feito, que é a pergunta.
    expect do
      Availability::GlobalTemplateService.destroy(id: raiz.id)
    end.to raise_error(ActiveRecord::StatementInvalid)

    expect(GlobalAvailabilityTemplate.where(id: [raiz.id, filho.id, neto.id]).count).to eq(3)
    expect(do_projeto.reload.global_availability_template_id).to eq(filho.id)
  end

  it 'id inexistente responde 404, e id que não é UUID também — sem estourar' do
    delete "/api/v1/availability_templates/#{SecureRandom.uuid}", headers: headers
    expect(response).to have_http_status(:not_found)

    delete '/api/v1/availability_templates/nao-e-uuid', headers: headers
    expect(response).to have_http_status(:not_found)
  end
end

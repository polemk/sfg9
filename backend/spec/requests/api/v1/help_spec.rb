# frozen_string_literal: true

require 'rails_helper'

# S12 — central de ajuda, FAQ e ajuda de campo (BE-350..BE-363, OPS-545).
RSpec.describe 'Ajuda e FAQ', type: :request do
  before { UserType.seed_default_types! }

  let(:og) { create(:user, :og) }
  let(:admin) { create(:user, :admin) }
  let(:gerente) { create(:user, :gerente) }
  let(:colaborador) { create(:user, :colaborador) }

  let(:grupo) { create(:help_group, title: 'Primeiros passos') }
  let(:categoria) { create(:help_category, group: grupo, title: 'Dúvidas frequentes') }

  def criar_item(titulo:, corpo:, categoria_alvo: categoria, autor: og)
    item = HelpItem.new(category: categoria_alvo, title: titulo, user_id: autor.id)
    item.description = corpo
    item.save!
    item
  end

  # -------------------------------------------------------------------
  # 5.18 / BE-363 / D-57 — no legado, TODOS os 4 controllers respondiam
  # sem usuário logado. Só o CSRF protegia a escrita.
  # -------------------------------------------------------------------
  describe 'autorização' do
    it 'sem sessão, NENHUM endpoint responde' do
      [['/api/v1/faq', :get], ['/api/v1/help_groups', :get], ['/api/v1/help_items', :get],
       ['/api/v1/help/fields', :get]].each do |caminho, verbo|
        public_send(verbo, caminho)
        expect(response).to have_http_status(:unauthorized), "#{caminho} respondeu sem sessão"
      end
    end

    it 'o FAQ é leitura para QUALQUER autenticado' do
      categoria
      %i[og admin gerente colaborador].each do |papel|
        get '/api/v1/faq', headers: auth_headers(create(:user, papel))
        expect(response).to have_http_status(:ok)
      end
    end

    it 'a escrita da central é só de papel administrativo' do
      post '/api/v1/help_groups', params: { title: 'X' }, headers: auth_headers(gerente)
      expect(response).to have_http_status(:forbidden)

      post '/api/v1/help_groups', params: { title: 'X' }, headers: auth_headers(colaborador)
      expect(response).to have_http_status(:forbidden)

      post '/api/v1/help_groups', params: { title: 'X' }, headers: auth_headers(admin)
      expect(response).to have_http_status(:created)
    end
  end

  # -------------------------------------------------------------------
  # 5.13 / BE-350 / BE-362 / D-58 — a busca olha o CONTEÚDO RICO
  # -------------------------------------------------------------------
  describe 'busca no conteúdo rico' do
    it 'acha item antigo (texto simples) e item novo (rich text) pela MESMA busca' do
      antigo = criar_item(titulo: 'Item de 2018', corpo: 'Fale de prorrogação de prazo.')
      novo = criar_item(titulo: 'Item de 2024', corpo: '<p>Fale de <strong>prorrogação</strong> de prazo.</p>')

      get '/api/v1/faq/search', params: { q: 'prorrogação' }, headers: auth_headers(colaborador)

      ids = JSON.parse(response.body).map { |i| i['id'] }
      expect(ids).to contain_exactly(antigo.id, novo.id)
    end

    it 'ignora acento nos dois sentidos' do
      criar_item(titulo: 'Manutenção', corpo: '<p>endereço</p>')

      get '/api/v1/faq/search', params: { q: 'manutencao' }, headers: auth_headers(colaborador)
      expect(JSON.parse(response.body).size).to eq(1)

      get '/api/v1/faq/search', params: { q: 'ENDERECO' }, headers: auth_headers(colaborador)
      expect(JSON.parse(response.body).size).to eq(1)
    end

    it 'o termo `0` NÃO casa a base inteira — não existe `OR id = q.to_i`' do
      # Títulos sem dígito de propósito: o que se está provando é que o `0` não
      # entra numa comparação de ID, não que ele nunca case texto nenhum.
      %w[Primeiro Segundo Terceiro].each { |t| criar_item(titulo: t, corpo: '<p>texto</p>') }

      get '/api/v1/faq/search', params: { q: '0' }, headers: auth_headers(colaborador)
      expect(JSON.parse(response.body)).to eq([])
    end

    it 'não casa nome de TAG do HTML' do
      criar_item(titulo: 'Com formatação', corpo: '<p><strong>importante</strong></p>')

      get '/api/v1/faq/search', params: { q: 'strong' }, headers: auth_headers(colaborador)
      expect(JSON.parse(response.body)).to eq([])
    end

    it 'a ordem é estável entre requisições' do
      3.times { |i| criar_item(titulo: "Item #{i}", corpo: '<p>alvo</p>') }

      duas = 2.times.map do
        get '/api/v1/faq/search', params: { q: 'alvo' }, headers: auth_headers(colaborador)
        JSON.parse(response.body).map { |i| i['id'] }
      end
      expect(duas.first).to eq(duas.last)
    end

    it 'devolve o trecho em volta do termo' do
      criar_item(titulo: 'Longo', corpo: "<p>#{'palavra ' * 40}alvo #{'depois ' * 40}</p>")

      get '/api/v1/faq/search', params: { q: 'alvo' }, headers: auth_headers(colaborador)
      expect(JSON.parse(response.body).first['excerpt']).to include('alvo')
    end
  end

  # -------------------------------------------------------------------
  # BE-350 — categoria OBRIGATÓRIA
  # -------------------------------------------------------------------
  describe 'GET /api/v1/faq/items' do
    it 'sem categoria, é erro de PARÂMETRO — não lista vazia silenciosa' do
      get '/api/v1/faq/items', headers: auth_headers(colaborador)
      expect(response).to have_http_status(:bad_request)
    end

    it 'categoria inexistente é 404, não `NoMethodError`' do
      get '/api/v1/faq/items', params: { category_id: SecureRandom.uuid }, headers: auth_headers(colaborador)
      expect(response).to have_http_status(:not_found)
    end

    it 'lista os itens da categoria, com o corpo' do
      criar_item(titulo: 'Um', corpo: '<p>conteúdo um</p>')
      get '/api/v1/faq/items', params: { category_id: categoria.id }, headers: auth_headers(colaborador)

      corpo = JSON.parse(response.body)
      expect(corpo.first['description_html']).to include('conteúdo um')
    end
  end

  # -------------------------------------------------------------------
  # 5.14 / BE-351 — a contagem total
  # -------------------------------------------------------------------
  describe 'contagem total na central' do
    it 'com mais de 30 itens, o total vem no envelope e o offset avança' do
      35.times { |i| criar_item(titulo: "Item #{i}", corpo: '<p>x</p>') }

      get '/api/v1/help_items', params: { per_page: 30, page: 1 }, headers: auth_headers(og)
      expect(response.headers['X-Total-Count']).to eq('35')
      pagina1 = JSON.parse(response.body).map { |i| i['id'] }

      get '/api/v1/help_items', params: { per_page: 30, page: 2 }, headers: auth_headers(og)
      pagina2 = JSON.parse(response.body).map { |i| i['id'] }

      expect(pagina1.size).to eq(30)
      expect(pagina2.size).to eq(5)
      expect(pagina1 & pagina2).to be_empty
    end
  end

  # -------------------------------------------------------------------
  # 5.15 / BE-352 — corpo vazio é REJEITADO
  # -------------------------------------------------------------------
  describe 'POST /api/v1/help_items' do
    it 'corpo vazio responde erro — no legado a validação nunca falhava' do
      post '/api/v1/help_items',
           params: { help_category_id: categoria.id, title: 'Sem corpo', description: '<p> </p>' },
           headers: auth_headers(og)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['message']).to match(/branco/i)
    end

    it 'título repetido na MESMA categoria é recusado' do
      criar_item(titulo: 'Repetido', corpo: '<p>a</p>')
      post '/api/v1/help_items',
           params: { help_category_id: categoria.id, title: 'Repetido', description: '<p>b</p>' },
           headers: auth_headers(og)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'o autor é o da SESSÃO, nunca o do payload' do
      post '/api/v1/help_items',
           params: { help_category_id: categoria.id, title: 'Novo', description: '<p>x</p>',
                     user_id: colaborador.id },
           headers: auth_headers(admin)

      expect(HelpItem.last.user_id).to eq(admin.id)
    end
  end

  # -------------------------------------------------------------------
  # 5.19 / FE-366 — a autoria é PRESERVADA na edição
  # -------------------------------------------------------------------
  describe 'PUT /api/v1/help_items/:id' do
    it 'editar item de outro autor NÃO reescreve a autoria' do
      item = criar_item(titulo: 'Do OG', corpo: '<p>a</p>', autor: og)

      put "/api/v1/help_items/#{item.id}", params: { title: 'Editado pelo Admin' },
                                           headers: auth_headers(admin)

      item.reload
      expect(item.user_id).to eq(og.id)
      expect(item.last_updated_user_id).to eq(admin.id)
    end

    it 'id inexistente responde 404 — nunca 500' do
      put "/api/v1/help_items/#{SecureRandom.uuid}", params: { title: 'X' }, headers: auth_headers(og)
      expect(response).to have_http_status(:not_found)
    end

    it 'o fallback `account_id` do legado NÃO existe' do
      item = criar_item(titulo: 'Alvo', corpo: '<p>a</p>')
      put "/api/v1/help_items/#{SecureRandom.uuid}", params: { account_id: item.id, title: 'X' },
                                                     headers: auth_headers(og)
      expect(response).to have_http_status(:not_found)
      expect(item.reload.title).to eq('Alvo')
    end
  end

  # -------------------------------------------------------------------
  # 5.16 — falha responde ERRO; 404 em vez de 500
  # -------------------------------------------------------------------
  describe 'falhas respondem erro' do
    it 'grupo, categoria e item inexistentes respondem 404' do
      [['/api/v1/help_groups', :put], ['/api/v1/help_categories', :put], ['/api/v1/help_items', :put]]
        .each do |base, verbo|
        public_send(verbo, "#{base}/#{SecureRandom.uuid}", params: { title: 'X' }, headers: auth_headers(og))
        expect(response).to have_http_status(:not_found), "#{base} não respondeu 404"
      end
    end
  end

  # -------------------------------------------------------------------
  # 5.17 / BE-357 / BE-360 — cascata transacional, com contagem do SERVIDOR
  # -------------------------------------------------------------------
  describe 'exclusão em cascata' do
    it 'a confirmação recebe do servidor a contagem exata da subárvore' do
      outra = create(:help_category, group: grupo)
      2.times { |i| criar_item(titulo: "A#{i}", corpo: '<p>x</p>') }
      3.times { |i| criar_item(titulo: "B#{i}", corpo: '<p>x</p>', categoria_alvo: outra) }

      get "/api/v1/help_groups/#{grupo.id}/impact", headers: auth_headers(og)
      expect(JSON.parse(response.body)).to eq('categories' => 2, 'items' => 5)

      get "/api/v1/help_categories/#{outra.id}/impact", headers: auth_headers(og)
      expect(JSON.parse(response.body)).to eq('categories' => 0, 'items' => 3)
    end

    it 'apagar o grupo leva categorias e itens, sem deixar órfão' do
      criar_item(titulo: 'Some junto', corpo: '<p>x</p>')

      delete "/api/v1/help_groups/#{grupo.id}", headers: auth_headers(og)

      expect(response).to have_http_status(:ok)
      expect(HelpCategory.count).to eq(0)
      expect(HelpItem.count).to eq(0)
    end

    it 'falha no meio da cascata NÃO deixa órfão' do
      criar_item(titulo: 'Preso', corpo: '<p>x</p>')
      allow_any_instance_of(HelpItem).to receive(:destroy).and_raise(ActiveRecord::RecordNotDestroyed)

      expect { Help::Tree.destroy_group!(grupo) }.to raise_error(ActiveRecord::RecordNotDestroyed)
      expect(HelpGroup.count).to eq(1)
      expect(HelpCategory.count).to eq(1)
      expect(HelpItem.count).to eq(1)
    end
  end

  # -------------------------------------------------------------------
  # DB-367 / DB-368 / BE-356 / BE-358
  # -------------------------------------------------------------------
  describe 'árvore, slug e ordem' do
    it 'o slug da categoria é PERSISTIDO, único e desambiguado' do
      a = create(:help_category, group: grupo, title: 'Dúvidas frequentes')
      b = create(:help_category, group: create(:help_group), title: 'Duvidas frequentes')

      expect(a.slug).to eq('duvidas-frequentes')
      expect(b.slug).to eq('duvidas-frequentes-2')
    end

    it 'renomear a categoria NÃO muda o slug — o deep-link continua válido' do
      categoria
      slug = categoria.slug
      put "/api/v1/help_categories/#{categoria.id}", params: { title: 'Outro nome' }, headers: auth_headers(og)
      expect(categoria.reload.slug).to eq(slug)
    end

    it 'mover a categoria de grupo leva os itens junto' do
      item = criar_item(titulo: 'Vai junto', corpo: '<p>x</p>')
      destino = create(:help_group, title: 'Destino')

      put "/api/v1/help_categories/#{categoria.id}", params: { help_group_id: destino.id },
                                                     headers: auth_headers(og)

      expect(categoria.reload.help_group_id).to eq(destino.id)
      expect(item.reload.category.group).to eq(destino)
    end

    it 'a ordem do grupo é PERSISTIDA, não `title ASC` da view' do
      primeiro = create(:help_group, title: 'Zebra')
      segundo = create(:help_group, title: 'Abelha')

      expect(HelpGroup.ordered.pluck(:title)).to eq(%w[Zebra Abelha])
      expect(primeiro.position).to be < segundo.position
    end

    it 'BE-358 — `user_id` não é aceito na criação do grupo (a coluna não existe)' do
      post '/api/v1/help_groups', params: { title: 'Com autor', user_id: og.id }, headers: auth_headers(og)
      expect(response).to have_http_status(:created)
      expect(HelpGroup.column_names).not_to include('user_id')
    end

    it 'campo não declarado (`is_editing`) é ignorado sem erro' do
      post '/api/v1/help_categories',
           params: { help_group_id: grupo.id, title: 'Nova', is_editing: true },
           headers: auth_headers(og)
      expect(response).to have_http_status(:created)
    end

    it 'título de categoria é único DENTRO do grupo, e livre entre grupos' do
      create(:help_category, group: grupo, title: 'Igual')

      post '/api/v1/help_categories', params: { help_group_id: grupo.id, title: 'Igual' },
                                      headers: auth_headers(og)
      expect(response).to have_http_status(:unprocessable_content)

      post '/api/v1/help_categories', params: { help_group_id: create(:help_group).id, title: 'Igual' },
                                      headers: auth_headers(og)
      expect(response).to have_http_status(:created)
    end
  end

  # -------------------------------------------------------------------
  # OPS-545 / DEC-88 — a ajuda de campo
  # -------------------------------------------------------------------
  describe 'ajuda de campo (OPS-545)' do
    it 'devolve o mapa `coluna → texto` dos três formulários' do
      get '/api/v1/help/fields', headers: auth_headers(colaborador)

      corpo = JSON.parse(response.body)
      expect(corpo.keys).to match_array(%w[receivables risk_operations structured_operations])
      expect(corpo['receivables']['valor_bruto']).to include('Valor de face')
    end

    # DEC-111 — os 4 `TODO:` foram fechados. Três ganharam texto (o que o campo faz
    # NO SISTEMA é verificável: nada o lê); o `resource_kind_id` saiu junto com a
    # entidade, pela DEC-110.
    it 'nenhuma chave sobrou como `TODO:`' do
      get '/api/v1/help/fields', headers: auth_headers(colaborador)
      corpo = JSON.parse(response.body)

      expect(corpo['receivables']['contrato']).to include('nenhum cálculo o lê')
      expect(corpo['risk_operations']['is_on_variable']).to include('copiado para a operação nova')
      expect(corpo['structured_operations']['is_on_variable']).to include('Marcador de cadastro')

      expect(corpo.values.flat_map(&:values)).to all(satisfy { |t| !t.start_with?('TODO:') })
    end

    it '`resource_kind_id` não tem ajuda porque a entidade não existe (DEC-110)' do
      get '/api/v1/help/fields', headers: auth_headers(colaborador)
      corpo = JSON.parse(response.body)

      expect(corpo['receivables']).not_to have_key('resource_kind_id')
    end

    it 'não há mais pendência de texto de ajuda' do
      expect(Help::FieldHelp.pending_keys.values.flatten).to be_empty
    end

    it 'chave ausente devolve nil, sem quebrar' do
      expect(Help::FieldHelp.text_for('receivables', 'campo_que_nao_existe')).to be_nil
      expect(Help::FieldHelp.for_scope('escopo_inexistente')).to eq({})
    end

    it 'um escopo por vez' do
      get '/api/v1/help/fields', params: { scope: 'risk_operations' }, headers: auth_headers(colaborador)
      expect(JSON.parse(response.body).keys).to eq(['risk_operations'])
    end

    it 'escopo desconhecido é erro de parâmetro' do
      get '/api/v1/help/fields', params: { scope: 'inventado' }, headers: auth_headers(colaborador)
      expect(response).to have_http_status(:bad_request)
    end
  end
end

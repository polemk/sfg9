# frozen_string_literal: true

require 'rails_helper'

# O despachante ficou sem NENHUMA tool entre o trim e a chegada do assistente:
#
# - `capture_lead` / `redirect_to_dashboard` (capability `lead_capture`) —
#   AI9-006, removidas no Bloco 6. Gravavam no `Lead`.
# - `search_operation_assets` / `list_all_operation_assets` (capability `assets`)
#   — AI9-014, removidas no Bloco 7. Faziam busca semântica sobre `OperationAsset`.
#
# O contrato que este spec protegia — tool desconhecida devolve
# `{ success: false }` em vez de estourar — continua valendo. O que ele passa a
# proteger junto é **o escopo**, e é a parte que importa: a ferramenta roda
# depois do controller, sem `current_user` e sem `current_project!`. Se ela lesse
# a partir do id que a sessão guardou, o assistente viraria a porta lateral para
# o dado de outro projeto.
RSpec.describe Ai::Tools::ToolExecutor do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:flow)     { create(:chat_flow) }
  let(:gerente)  { create(:user, user_type: UserType.gerente) }
  let(:estranho) { create(:user, user_type: UserType.gerente) }

  let!(:projeto_a) { create_project_with_owner(gerente, name: 'Carteira A') }
  let!(:projeto_b) { create_project_with_owner(gerente, name: 'Carteira B') }

  let(:hoje) { Date.new(2026, 6, 15) }

  def sessao_de(user)
    create(:chat_session, chat_flow: flow, user: user)
  end

  def executar(tool, args = {}, user: gerente)
    described_class.execute(tool, args, flow: flow, session: sessao_de(user))
  end

  def payload(resultado)
    JSON.parse(resultado[:message])
  end

  describe 'o contrato do despachante' do
    it 'devolve falha estruturada para uma tool que não existe, sem levantar' do
      resultado = executar('tool_inexistente', { 'x' => 1 })

      expect(resultado[:success]).to be false
      expect(resultado[:message]).to include('Unknown tool')
    end

    it 'trata as tools removidas como desconhecidas' do
      %w[capture_lead redirect_to_dashboard search_operation_assets list_all_operation_assets].each do |tool|
        expect(described_class.execute(tool, {}, flow: flow, session: sessao_de(gerente))[:success]).to be false
      end
    end

    it 'sem sessão não há dono, e sem dono não lê nada' do
      resultado = described_class.execute('project_snapshot', {}, flow: nil)

      expect(resultado[:success]).to be false
      expect(resultado[:message]).to eq(Ai::Tools::ConsoleScope::SEM_DONO)
    end

    # O laço de tool calling espera sempre `{ success:, message: }`. Uma exceção
    # subindo daqui derrubaria o turno inteiro, e o usuário veria o fallback
    # genérico em vez da recusa que explica o que fazer.
    it 'erro no handler vira recusa, não exceção' do
      allow(Ai::Tools::Handlers::ConsoleData).to receive(:project_snapshot).and_raise(StandardError, 'boom')
      gerente.update!(current_project_id: projeto_a.id)

      resultado = executar('project_snapshot')

      expect(resultado[:success]).to be false
      expect(resultado[:message]).not_to include('boom')
    end

    it 'aceita argumento com chave símbolo ou string' do
      create(:help_item, title: 'Como lançar um borderô')

      por_string = executar('search_faq', { 'term' => 'borderô' })
      por_simbolo = executar('search_faq', { term: 'borderô' })

      expect(payload(por_string)['count']).to eq(1)
      expect(payload(por_simbolo)['count']).to eq(1)
    end
  end

  describe 'o projeto selecionado é o escopo de toda leitura de dado' do
    let!(:bordero_a) do
      create(:receivable_entry, project: projeto_a, date: Date.new(2026, 5, 10), valor_bruto: BigDecimal('50000.00'))
    end
    let!(:bordero_b) do
      create(:receivable_entry, project: projeto_b, date: Date.new(2026, 5, 10), valor_bruto: BigDecimal('12345.00'))
    end

    it 'responde com o projeto corrente, e não com o outro em que a pessoa também participa' do
      gerente.update!(current_project_id: projeto_a.id)

      corpo = payload(executar('project_snapshot', { 'date' => hoje.to_s }))
      total = corpo['cards'].find { |c| c['key'] == 'total_operado' }

      expect(corpo['project']).to eq('Carteira A')
      expect(total['value']).to eq('50.000,00')
    end

    it 'acompanha a troca de projeto sem precisar de sessão nova' do
      gerente.update!(current_project_id: projeto_b.id)

      corpo = payload(executar('project_snapshot', { 'date' => hoje.to_s }))

      expect(corpo['project']).to eq('Carteira B')
      expect(corpo['cards'].find { |c| c['key'] == 'total_operado' }['value']).to eq('12.345,00')
    end

    it 'sem projeto escolhido, pede a escolha em vez de somar tudo' do
      resultado = executar('project_snapshot')

      expect(resultado[:success]).to be false
      expect(resultado[:message]).to eq(Ai::Tools::ConsoleScope::SEM_PROJETO)
    end

    it 'projeto de outra pessoa gravado na coluna não é lido' do
      alheio = create_project_with_owner(estranho, name: 'Carteira alheia')
      gerente.update!(current_project_id: alheio.id)

      resultado = executar('project_snapshot')

      expect(resultado[:success]).to be false
      expect(resultado[:message]).to eq(Ai::Tools::ConsoleScope::SEM_PROJETO)
    end

    # As três ferramentas de dado passam pelo mesmo portão — o spec cobre as três
    # porque "esqueci o portão neste handler" é o defeito que ele existe para
    # pegar, e ele só aparece na ferramenta esquecida.
    it 'as três ferramentas de dado exigem projeto' do
      %w[project_snapshot overdue_renegotiations volume_by_carrier].each do |tool|
        expect(executar(tool)[:success]).to be(false), "#{tool} respondeu sem projeto corrente"
      end
    end
  end

  describe 'ausência não é zero (D-117)' do
    it 'total operado sem borderô no período vem como ausente, não como 0,00' do
      gerente.update!(current_project_id: projeto_a.id)

      corpo = payload(executar('project_snapshot', { 'date' => hoje.to_s }))
      total = corpo['cards'].find { |c| c['key'] == 'total_operado' }

      expect(total['has_value']).to be false
      expect(total['value']).to be_nil
    end
  end

  describe 'as ferramentas de ajuda' do
    let!(:item) { create(:help_item, title: 'Como lançar um borderô', description: '<p>Abra a tela de recebíveis.</p>') }

    it 'busca no acervo e devolve o trecho' do
      corpo = payload(executar('search_faq', { 'term' => 'borderô' }))

      expect(corpo['count']).to eq(1)
      expect(corpo['items'].first['title']).to eq('Como lançar um borderô')
    end

    # Zero resultado é RESPOSTA: diz que o acervo não cobre o assunto, e é o que
    # impede o agente de preencher a lacuna com suposição.
    it 'termo sem resultado devolve sucesso com lista vazia' do
      resultado = executar('search_faq', { 'term' => 'assunto que ninguém escreveu' })

      expect(resultado[:success]).to be true
      expect(payload(resultado)['count']).to eq(0)
    end

    it 'lê o corpo completo em texto puro, sem a marcação' do
      corpo = payload(executar('read_faq_item', { 'id' => item.id.to_s }))

      expect(corpo['body']).to include('Abra a tela de recebíveis.')
      expect(corpo['body']).not_to include('<p>')
    end

    it 'item inexistente recusa em vez de estourar' do
      expect(executar('read_faq_item', { 'id' => '0' })[:success]).to be false
    end

    it 'devolve a ajuda de campo de um formulário inteiro' do
      corpo = payload(executar('field_help', { 'scope' => 'receivables' }))

      expect(corpo['scope']).to eq('receivables')
      expect(corpo['fields']).to be_a(Hash)
    end

    it 'formulário desconhecido recusa nomeando os que existem' do
      resultado = executar('field_help', { 'scope' => 'inexistente' })

      expect(resultado[:success]).to be false
      expect(resultado[:message]).to include('receivables')
    end

    # Ajuda não é dado de projeto: negá-la a quem ainda não escolheu um deixaria
    # o assistente mudo justamente para quem acabou de entrar.
    it 'responde ajuda mesmo sem projeto corrente' do
      expect(executar('search_faq', { 'term' => 'borderô' })[:success]).to be true
    end
  end
end

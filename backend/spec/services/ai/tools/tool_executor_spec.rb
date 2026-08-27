# frozen_string_literal: true

require 'rails_helper'

# ESTADO APÓS O TRIM (Phase 1b): o despachante não tem NENHUMA tool registrada.
#
# - `capture_lead` / `redirect_to_dashboard` saíram no Bloco 6 com o AI9-006 —
#   gravavam no `Lead` via `Leads::UpsertFromChat`.
# - `search_operation_assets` / `list_all_operation_assets` saíram no Bloco 7 com
#   o AI9-014 — faziam busca semântica (`pgvector`) sobre `OperationAsset`.
#
# O que este spec protege é o contrato do despachante, que continua sendo o ponto
# de extensão do assistente interno (AI9-007, mantido pelo DEC-13.2): tool
# desconhecida devolve `{ success: false }` em vez de estourar.
RSpec.describe Ai::Tools::ToolExecutor do
  let(:chat_flow) { create(:chat_flow) }
  let(:session) { create(:chat_session, chat_flow: chat_flow) }

  describe '.execute' do
    it 'devolve falha estruturada para uma tool que não existe, sem levantar' do
      result = described_class.execute('tool_inexistente', { 'x' => 1 }, flow: chat_flow, session: session)

      expect(result[:success]).to be false
      expect(result[:message]).to include('Unknown tool')
    end

    it 'trata as tools removidas como desconhecidas' do
      %w[capture_lead redirect_to_dashboard search_operation_assets list_all_operation_assets].each do |tool|
        result = described_class.execute(tool, {}, flow: chat_flow, session: session)
        expect(result[:success]).to be false
      end
    end

    it 'não exige sessão para responder' do
      result = described_class.execute('qualquer', {}, flow: nil)
      expect(result[:success]).to be false
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::FlowMatcher do
  describe '.match' do
    let!(:support_flow) { create(:chat_flow, name: 'Support', keywords: ['help', 'suporte']) }
    let!(:sales_flow) { create(:chat_flow, name: 'Sales', keywords: ['buy', 'price', 'preço']) }
    let!(:empty_flow) { create(:chat_flow, name: 'Empty', keywords: []) }

    context 'when text is blank' do
      it 'returns nil' do
        expect(described_class.match(nil)).to be_nil
        expect(described_class.match('')).to be_nil
        expect(described_class.match('   ')).to be_nil
      end
    end

    context 'when no keyword matches' do
      it 'returns nil' do
        expect(described_class.match('hello world')).to be_nil
      end
    end

    context 'when a keyword matches exactly' do
      it 'returns the matching flow' do
        expect(described_class.match('help')).to eq(support_flow)
        expect(described_class.match('PRICE')).to eq(sales_flow)
      end
    end

    context 'when input contains the keyword' do
      it 'returns the matching flow' do
        expect(described_class.match('I need help please')).to eq(support_flow)
        expect(described_class.match('qual o preço do plano?')).to eq(sales_flow)
      end
    end

    context 'when flows have no keywords' do
      it 'ignores flows with empty keywords' do
        expect(described_class.match('empty')).to be_nil
      end
    end
  end

  # Bloco 7 do trim (AI9-014): `.match_by_operation` e `.match_by_operation_keyword`
  # saíram com o `Operation` — a primeira usava embeddings
  # (`Operations::IntentDetectorService`) e a segunda `Operation#matches_text?`.
  # O `.match` passou a ser só o casamento por `chat_flows.keywords`.

  describe '.match_by_keyword' do
    let!(:support_flow) { create(:chat_flow, name: 'Support', keywords: ['help', 'suporte']) }
    let!(:sales_flow) { create(:chat_flow, name: 'Sales', keywords: ['buy', 'price']) }
    let!(:empty_flow) { create(:chat_flow, name: 'Empty', keywords: []) }

    context 'when text is blank' do
      it 'returns nil' do
        expect(described_class.match_by_keyword(nil)).to be_nil
        expect(described_class.match_by_keyword('')).to be_nil
      end
    end

    context 'when keyword matches' do
      it 'returns the matching flow (case insensitive)' do
        expect(described_class.match_by_keyword('HELP me')).to eq(support_flow)
        expect(described_class.match_by_keyword('what is the price?')).to eq(sales_flow)
      end
    end

    context 'when no keyword matches' do
      it 'returns nil' do
        expect(described_class.match_by_keyword('hello world')).to be_nil
      end
    end
  end
end

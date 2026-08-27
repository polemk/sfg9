# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Providers::GoogleProvider do
  let(:api_key) { 'test-google-key' }
  subject(:provider) { described_class.new(api_key) }

  describe '#chat_completion' do
    let(:system_prompt) { 'You are a helpful assistant.' }
    let(:model) { 'gemini-2.0-flash' }

    before do
      stub_request(:post, %r{https://generativelanguage\.googleapis\.com/v1beta/models/.*:generateContent})
        .to_return(status: 200, body: {
          candidates: [{ content: { parts: [{ text: 'AI response text' }] } }]
        }.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    context 'with text-only messages' do
      let(:messages) { [{ role: 'user', content: 'Hello' }] }

      it 'sends standard text parts' do
        result = provider.chat_completion(system_prompt: system_prompt, messages: messages, model: model)
        expect(result).to eq('AI response text')

        expect(WebMock).to have_requested(:post, %r{generateContent})
          .with { |req|
            body = JSON.parse(req.body)
            parts = body['contents'][0]['parts']
            parts.length == 1 && parts[0]['text'] == 'Hello'
          }
      end
    end

    context 'with multimodal messages (text + image)' do
      let(:image_data) { { base64: 'aW1hZ2VfZGF0YQ==', mime_type: 'image/webp' } }
      let(:messages) { [{ role: 'user', content: 'Describe this', image_data: image_data }] }

      it 'sends inlineData part alongside text' do
        provider.chat_completion(system_prompt: system_prompt, messages: messages, model: model)

        expect(WebMock).to have_requested(:post, %r{generateContent})
          .with { |req|
            body = JSON.parse(req.body)
            parts = body['contents'][0]['parts']
            parts.length == 2 &&
              parts[0]['inlineData']['mimeType'] == 'image/webp' &&
              parts[0]['inlineData']['data'] == 'aW1hZ2VfZGF0YQ==' &&
              parts[1]['text'] == 'Describe this'
          }
      end
    end

    context 'with image but no text' do
      let(:image_data) { { base64: 'aW1hZ2VfZGF0YQ==', mime_type: 'image/png' } }
      let(:messages) { [{ role: 'user', content: nil, image_data: image_data }] }

      it 'sends only the inlineData part' do
        provider.chat_completion(system_prompt: system_prompt, messages: messages, model: model)

        expect(WebMock).to have_requested(:post, %r{generateContent})
          .with { |req|
            body = JSON.parse(req.body)
            parts = body['contents'][0]['parts']
            parts.length == 1 && parts[0].key?('inlineData')
          }
      end
    end
  end
end

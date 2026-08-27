# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Providers::AnthropicProvider do
  let(:api_key) { 'test-anthropic-key' }
  subject(:provider) { described_class.new(api_key) }

  describe '#chat_completion' do
    let(:system_prompt) { 'You are a helpful assistant.' }
    let(:model) { 'claude-3-5-sonnet-20241022' }

    before do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 200, body: {
          content: [{ type: 'text', text: 'AI response text' }]
        }.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    context 'with text-only messages' do
      let(:messages) { [{ role: 'user', content: 'Hello' }] }

      it 'sends standard text messages' do
        result = provider.chat_completion(system_prompt: system_prompt, messages: messages, model: model)
        expect(result).to eq('AI response text')

        expect(WebMock).to have_requested(:post, 'https://api.anthropic.com/v1/messages')
          .with { |req|
            body = JSON.parse(req.body)
            msgs = body['messages']
            msgs.length == 1 && msgs[0]['content'] == 'Hello'
          }
      end
    end

    context 'with multimodal messages (text + image)' do
      let(:image_data) { { base64: 'aW1hZ2VfZGF0YQ==', mime_type: 'image/jpeg' } }
      let(:messages) { [{ role: 'user', content: 'Describe this image', image_data: image_data }] }

      it 'sends content as an array of image + text blocks' do
        result = provider.chat_completion(system_prompt: system_prompt, messages: messages, model: model)
        expect(result).to eq('AI response text')

        expect(WebMock).to have_requested(:post, 'https://api.anthropic.com/v1/messages')
          .with { |req|
            body = JSON.parse(req.body)
            content = body['messages'][0]['content']
            content.is_a?(Array) &&
              content[0]['type'] == 'image' &&
              content[0]['source']['type'] == 'base64' &&
              content[0]['source']['media_type'] == 'image/jpeg' &&
              content[0]['source']['data'] == 'aW1hZ2VfZGF0YQ==' &&
              content[1]['type'] == 'text' &&
              content[1]['text'] == 'Describe this image'
          }
      end
    end

    context 'with image but no caption' do
      let(:image_data) { { base64: 'aW1hZ2VfZGF0YQ==', mime_type: 'image/png' } }
      let(:messages) { [{ role: 'user', content: nil, image_data: image_data }] }

      it 'sends only the image block without text' do
        provider.chat_completion(system_prompt: system_prompt, messages: messages, model: model)

        expect(WebMock).to have_requested(:post, 'https://api.anthropic.com/v1/messages')
          .with { |req|
            body = JSON.parse(req.body)
            content = body['messages'][0]['content']
            content.is_a?(Array) && content.length == 1 && content[0]['type'] == 'image'
          }
      end
    end
  end
end

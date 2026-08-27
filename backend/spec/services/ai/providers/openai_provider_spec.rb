# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Providers::OpenaiProvider do
  let(:api_key) { 'test-openai-key' }
  subject(:provider) { described_class.new(api_key) }

  describe '#chat_completion' do
    let(:system_prompt) { 'You are a helpful assistant.' }
    let(:model) { 'gpt-4o' }

    before do
      stub_request(:post, 'https://api.openai.com/v1/chat/completions')
        .to_return(status: 200, body: {
          choices: [{ message: { content: 'AI response text' } }]
        }.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    context 'with text-only messages' do
      let(:messages) { [{ role: 'user', content: 'Hello' }] }

      it 'sends standard text messages with system prompt' do
        result = provider.chat_completion(system_prompt: system_prompt, messages: messages, model: model)
        expect(result).to eq('AI response text')

        expect(WebMock).to have_requested(:post, 'https://api.openai.com/v1/chat/completions')
          .with { |req|
            body = JSON.parse(req.body)
            msgs = body['messages']
            msgs[0]['role'] == 'system' &&
              msgs[1]['role'] == 'user' &&
              msgs[1]['content'] == 'Hello'
          }
      end
    end

    context 'with multimodal messages (text + image)' do
      let(:image_data) { { base64: 'aW1hZ2VfZGF0YQ==', mime_type: 'image/jpeg' } }
      let(:messages) { [{ role: 'user', content: 'Describe this', image_data: image_data }] }

      it 'sends content as an array with image_url + text parts' do
        provider.chat_completion(system_prompt: system_prompt, messages: messages, model: model)

        expect(WebMock).to have_requested(:post, 'https://api.openai.com/v1/chat/completions')
          .with { |req|
            body = JSON.parse(req.body)
            user_msg = body['messages'].find { |m| m['role'] == 'user' }
            content = user_msg['content']
            content.is_a?(Array) &&
              content[0]['type'] == 'image_url' &&
              content[0]['image_url']['url'] == 'data:image/jpeg;base64,aW1hZ2VfZGF0YQ==' &&
              content[1]['type'] == 'text' &&
              content[1]['text'] == 'Describe this'
          }
      end
    end
  end
end

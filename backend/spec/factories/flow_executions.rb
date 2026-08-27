# frozen_string_literal: true

FactoryBot.define do
  factory :flow_execution do
    association :chat_session
    association :chat_flow

    node_id { "node-#{SecureRandom.hex(4)}" }
    node_type { %w[trigger text message question input option redirect condition handoff].sample }
    input_data { {} }
    output_data { { 'content' => 'Test output' } }
    context_snapshot { {} }

    trait :trigger do
      node_type { 'trigger' }
      output_data { {} }
    end

    trait :text do
      node_type { 'text' }
      output_data { { 'content' => 'Hello, this is a message' } }
    end

    trait :question do
      node_type { 'question' }
      input_data { { 'user_input' => 'User response' } }
      output_data { { 'content' => 'What is your name?', 'variable' => 'name' } }
    end

    trait :option do
      node_type { 'option' }
      output_data { { 'content' => 'Choose an option', 'options' => %w[A B C] } }
    end

    trait :redirect do
      node_type { 'redirect' }
      output_data { { 'action' => 'scroll_to', 'target' => '#section' } }
    end

    trait :with_context do
      context_snapshot { { 'name' => 'John', 'email' => 'john@example.com' } }
    end
  end
end

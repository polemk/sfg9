FactoryBot.define do
  factory :chat_flow do
    name { "My Flow" }
    published { true }
    definition { { "nodes" => [] } }

    trait :onboarding do
      definition {
        {
          "nodes" => [
            { "id" => "start", "type" => "text", "content" => "Hello! Welcome.", "position" => { "x" => 0, "y" => 0 } },
            { "id" => "ask_name", "type" => "input", "inputType" => "text", "variable" => "name", "content" => "Name?", "position" => { "x" => 0, "y" => 100 } },
            { "id" => "greet", "type" => "text", "content" => "Hi {{name}}!", "position" => { "x" => 0, "y" => 200 } }
          ],
          "edges" => [
            { "id" => "e1", "source" => "start", "target" => "ask_name", "sourceHandle" => nil, "targetHandle" => nil },
            { "id" => "e2", "source" => "ask_name", "target" => "greet", "sourceHandle" => nil, "targetHandle" => nil }
          ]
        }
      }
    end
  end

  factory :chat_session do
    association :chat_flow 
    context { {} }
  end
end

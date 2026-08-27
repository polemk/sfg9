cf = ChatFlow.find_by(name: 'Maya')
session = ChatSession.new(
  chat_flow: cf,
  status: 'active',
  context: { 'name' => 'guilheme', 'email' => 'fds@polemk.com' },
  current_step_id: 'ask_phone'
)
session.save(validate: false)
engine = Ai::FlowEngine.new(session, '49999350241')
responses = engine.process!
puts "\n\n=== RESPONSES ===\n\n"
puts responses.to_json
puts "\n\n=== LOGS ===\n\n"

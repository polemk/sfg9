
flow = ChatFlow.find_by(name: 'Maya')
# Create a temporary session
session = ChatSession.create!(chat_flow: flow, status: 'active', context: {})

puts "Testando no fluxo '#{flow.name}' de ID #{flow.id}"
puts "Session ID: #{session.id}"

# Set initial state
session.update!(current_step_id: 'start')
puts "Estado inicial: #{session.current_step_id}"

input = "❓ O que é a FPK?"
puts "\nSimulando clique em '#{input}'"

engine = Ai::FlowEngine.new(session, input)
responses = engine.process!

puts "\nRESPONSES GENERATED:"
responses.each { |r| puts "- [#{r[:type] || 'node'}] #{(r[:content] || r[:id]).to_s.gsub(\"\n\", \" \")}" }

puts "\nNOVO ESTADO: #{session.reload.current_step_id}"

# Cleanup
session.destroy

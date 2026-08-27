
session = ChatSession.last
flow = session.chat_flow
input = "❓ O que é a FPK?"

puts "Simulando clique em '#{input}' no fluxo '#{flow.name}'"
puts "Estado atual: #{session.current_step_id}"

engine = Ai::FlowEngine.new(session, input)
responses = engine.process!

puts "\nRESPONSES GENERATED:"
responses.each { |r| puts "- [#{r[:type] || 'node'}] #{r[:content] || r[:id]}" }

puts "\nNOVO ESTADO: #{session.current_step_id}"

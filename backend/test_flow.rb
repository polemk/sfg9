require_relative 'config/environment'

flow = ChatFlow.find_by(name: 'Audio Visualizer Experiment')
lead = Lead.first || Lead.create!(name: 'Test Lead', phone: '000000')
session = ChatSession.create!(chat_flow: flow, lead: lead)
engine = Ai::FlowEngine.new(session)

puts "Starting flow..."
result = engine.process!
puts "Result: #{result.inspect}"

puts "\n--------------------------------------------------------------\n"

puts "Sending 'Sim, rock it'..."
engine = Ai::FlowEngine.new(session, "Sim, rock it")
result = engine.process!
puts "Result: #{result.inspect}"

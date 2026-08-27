lead = Lead.where("smart_id IS NOT NULL").last
integration = Integration.find_by(platform: 'instagram', status: 'active') || Integration.find_by(platform: 'messenger', status: 'active') || Integration.find_by(platform: 'waba', status: 'active')

puts "Using integration: #{integration&.platform}"
puts "Using lead: #{lead&.smart_id}"

message = LeadMessage.create!(
  lead: lead,
  sender_role: 'agent',
  content: 'Escolha uma das opções abaixo para continuarmos:',
  options_metadata: {
    quick_replies: [
      { title: 'Opção 1', payload: 'OPT1' },
      { title: 'Opção 2', payload: 'OPT2' }
    ]
  }.to_json,
  source_endpoint: 'chat' # just for local creation test, won't dispatch if it's 'chat'. 
)

# Test dispatch format parsing manually
quick_replies = nil
if message.options_metadata.present?
  metadata = JSON.parse(message.options_metadata)
  quick_replies = metadata['quick_replies']
end

puts "Parsed QA: #{quick_replies.inspect}"

require './config/environment'

begin
  puts "Testing NEW contextual..."
  res = ChatFlow.contextual("visitor", "/dashboard")
  puts "Res: #{res.inspect}"
rescue => e
  puts "ERROR: #{e.class} - #{e.message}"
  puts e.backtrace.first(5)
end

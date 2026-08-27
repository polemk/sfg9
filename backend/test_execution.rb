require './config/environment'

begin
  puts "Testing old contextual..."
  res = ChatFlow.where(target_user_type: "visitor", target_route_path: "/dashboard")
    .or(ChatFlow.where(target_user_type: "visitor", target_route_path: nil))
    .or(ChatFlow.where(target_user_type: nil, target_route_path: "/dashboard"))
    .order(Arel.sql("CASE WHEN target_route_path IS NOT NULL AND target_user_type IS NOT NULL THEN 0 
                           WHEN target_route_path IS NOT NULL THEN 1 
                           WHEN target_user_type IS NOT NULL THEN 2 
                           ELSE 3 END"))
  puts res.to_a.inspect
rescue => e
  puts "ERROR: #{e.class} - #{e.message}"
end

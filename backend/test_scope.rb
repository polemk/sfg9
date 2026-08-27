require './config/environment'

route_str = "/dashboard"
user_type = "visitor"

q = ChatFlow.where(
  "(? = ANY(mapped_routes) OR target_route_path = ?) AND target_user_type = ?", 
  route_str, route_str, user_type
).or(
  ChatFlow.where("(? = ANY(mapped_routes) OR target_route_path = ?) AND target_user_type IS NULL", 
  route_str, route_str)
).or(
  ChatFlow.where("mapped_routes = '{}' OR mapped_routes IS NULL").where(target_route_path: nil, target_user_type: user_type)
).order(Arel.sql(ChatFlow.sanitize_sql_array([
  "CASE 
     WHEN (? = ANY(mapped_routes) OR target_route_path = ?) AND target_user_type = ? THEN 0 
     WHEN (? = ANY(mapped_routes) OR target_route_path = ?) THEN 1 
     WHEN target_user_type = ? THEN 2 
     ELSE 3 
   END",
  route_str, route_str, user_type,
  route_str, route_str,
  user_type
])))

puts q.to_sql

puts "--- USER TYPES ---"
UserType.all.each { |ut| puts "ID: #{ut.id}, Name: #{ut.name}, Slug: #{ut.slug}" }
puts "------------------"

puts "--- RECENT USERS (Last 5) ---"
User.order(created_at: :desc).limit(5).each do |u|
  type_name = u.user_type&.name || 'N/A'
  puts "ID: #{u.id}, Name: #{u.name}, Email: #{u.email}, Type: #{type_name}"
end
puts "-----------------------------"

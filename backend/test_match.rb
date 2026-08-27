options = ["🚀 Bora!", "❓ O que é a FPK?"]
input = "❓ O que é a fpk?"
selected_idx = nil
options.each_with_index { |opt, i| selected_idx = i if opt.to_s.strip.downcase == input.to_s.strip.downcase }
puts "Selected Index: #{selected_idx.inspect}"

input2 = "❓ O que é a FPK?"
selected_idx2 = nil
options.each_with_index { |opt, i| selected_idx2 = i if opt.to_s.strip.downcase == input2.to_s.strip.downcase }
puts "Selected Index 2: #{selected_idx2.inspect}"

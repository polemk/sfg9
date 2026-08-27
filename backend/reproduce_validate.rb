# frozen_string_literal: true

puts "--- Testing Operation Update ---"
Operation.destroy_all

# Create initial op
op = Operation.create!(
  key: "initial_op",
  title: "Initial Operation",
  keywords: ["one", "two"],
  active: true
)

puts "Created op: #{op.id} - #{op.title} - #{op.key} - #{op.keywords}"

# Test Update
puts "\nUpdating op..."
begin
  params = {
    id: op.id,
    title: "Updated Operation",
    key: "initial_op", # Same key to test uniqueness check
    description: "Updated description",
    keywords: ["one", "two", "three"] # Updated keywords
  }
  
  # Mimic Service Logic
  params_copy = params.dup
  id = params_copy.delete(:id)
  operation = Operation.by_any_id(id)
  
  if operation
    # Mimic process_keywords_param - it does NOTHING if keywords is array
    if params_copy[:keywords].is_a?(Array)
       # do nothing
    end

    operation.update!(params_copy)
    puts "✅ Update SUCCESS!"
    puts "New keywords: #{operation.reload.keywords}"
  else
    puts "❌ Operation not found"
  end

rescue => e
  puts "❌ Update FAILED: #{e.message}"
  puts e.backtrace.first(5)
end

# Test Update invalid key
puts "\nTesting Duplicate Key Update..."
op2 = Operation.create!(key: "other_op", title: "Other", keywords: [])
begin
  op2.update!(key: "initial_op") # Should fail
  puts "❌ Should have failed uniqueness"
rescue => e
  puts "✅ Correctly failed: #{e.message}"
end
